import
  std/[unittest, httpclient, json, strutils, os, osproc],
  openapi, regen

## Test suite for the Regen Search API endpoints.
## Validates all HTTP endpoints, error handling, and response formats.
## Automatically starts and stops the server for testing.

const
  TestPort = 8888
  TestHost = "localhost"
  TestIndexName = "tests/tmp/test_index.flat"

suite "Regen Search API Tests":
  var 
    client: HttpClient
    baseUrl: string
    testIndexPath: string
    serverProcess: Process

  proc startTestServer(): Process =
    ## Start the API server process for testing.
    let process = startProcess("nim", args = @["c", "-r", "src/regen.nim", "--server", $TestPort], 
                              options = {poUsePath, poStdErrToStdOut})
    return process

  proc waitForServerReady(maxWaitSeconds: int = 10): bool =
    ## Wait for the server to be ready to accept connections.
    let testClient = newHttpClient()
    testClient.timeout = 1000  # 1 second timeout
    
    for i in 1..maxWaitSeconds:
      try:
        let response = testClient.get("http://" & TestHost & ":" & $TestPort & "/")
        if response.code == Http200:
          testClient.close()
          return true
      except:
        discard
      
      sleep(1000)  # Wait 1 second before retry
    
    testClient.close()
    return false

  proc stopTestServer(process: Process) =
    ## Stop the test server process.
    if process != nil:
      process.terminate()
      discard process.waitForExit()
      process.close()

  proc createTestIndex() =
    ## Create a minimal test index file for testing API endpoints.
    testIndexPath = TestIndexName
    
    # Create test files in memory for the index
    let testRepo = RegenGitRepo(
      name: "test_repo",
      latestCommitHash: "abc123",
      isDirty: false,
      files: @[
        RegenFile(
          path: "test.nim",
          filename: "test.nim", 
          hash: "hash123",
          creationTime: 0.0,
          lastModified: 0.0,
          fragments: @[
            RegenFragment(
              startLine: 1,
              endLine: 10,
              embedding: @[0.1'f32, 0.2, 0.3, 0.4, 0.5],
              fragmentType: "file",
              model: SimilarityEmbeddingModel,
              private: false,
              contentScore: 80,
              hash: "fragment123"
            )
          ]
        )
      ]
    )
    
    let testIndex = RegenIndex(
      version: "0.1.0",
      kind: regen_git_repo,
      repo: testRepo
    )
    
    writeIndexToFile(testIndex, testIndexPath)

  setup:
    client = newHttpClient()
    baseUrl = "http://" & TestHost & ":" & $TestPort
    createTestIndex()
    
    # Start the server and wait for it to be ready
    serverProcess = startTestServer()
    if not waitForServerReady():
      stopTestServer(serverProcess)
      quit(1)

  teardown:
    client.close()
    stopTestServer(serverProcess)
    if fileExists(testIndexPath):
      removeFile(testIndexPath)

  test "Health endpoint returns correct format":
    ## Test that the health endpoint returns proper JSON with expected fields.
    let response = client.get(baseUrl & "/")
    
    check response.code == Http200
    check "application/json" in response.headers.getOrDefault("Content-Type")
    
    let jsonResponse = parseJson(response.body)
    check jsonResponse["message"].getStr() == "Regen Search API"
    check jsonResponse["version"].getStr() == "1.0.0"
    check jsonResponse["endpoints"].kind == JArray
    check jsonResponse["endpoints"].len == 3

  test "OpenAPI spec endpoint returns valid JSON":
    ## Test that the OpenAPI specification endpoint returns valid OpenAPI 3.0 spec.
    let response = client.get(baseUrl & "/openapi.json")
    
    check response.code == Http200
    check "application/json" in response.headers.getOrDefault("Content-Type")
    
    let spec = parseJson(response.body)
    check spec["openapi"].getStr() == "3.0.3"
    check spec["info"]["title"].getStr() == "Regen Search API"
    check spec["info"]["version"].getStr() == "1.0.0"
    check spec.hasKey("paths")
    check spec["paths"].hasKey("/search/ripgrep")
    check spec["paths"].hasKey("/search/embedding")

  test "Ripgrep search with valid request":
    ## Test ripgrep search endpoint with a valid request and test index.
    let request = %*{
      "pattern": "test",
      "caseSensitive": true,
      "maxResults": 10,
      "indexPath": testIndexPath
    }
    
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let response = client.post(baseUrl & "/search/ripgrep", body = $request)
    
    check response.code == Http200
    
    let jsonResponse = parseJson(response.body)
    # API returns results structure for now, CLI uses ripgrep format
    check jsonResponse.hasKey("results") or jsonResponse.hasKey("matches")
    if jsonResponse.hasKey("results"):
      check jsonResponse["results"].kind == JArray
    else:
      check jsonResponse["matches"].kind == JArray

  test "Ripgrep search with missing index file":
    ## Test that ripgrep search returns 400 error for missing index files.
    let request = %*{
      "pattern": "test",
      "caseSensitive": true,
      "maxResults": 10,
      "indexPath": "./nonexistent.flat"
    }
    
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let response = client.post(baseUrl & "/search/ripgrep", body = $request)
    
    check response.code == Http400
    
    let jsonResponse = parseJson(response.body)
    check jsonResponse["error"].getStr().contains("Index file not found")
    check jsonResponse["code"].getInt() == 400

  test "Ripgrep search with invalid JSON":
    ## Test that invalid JSON requests are handled with proper error responses.
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let response = client.post(baseUrl & "/search/ripgrep", body = "{invalid json")
    
    check response.code == Http500  # Will be caught by general exception handler

  test "Embedding search with valid request":
    ## Test embedding search endpoint with valid request and test index.
    ## Note: May return 500 if embedding service (ollama) is not available.
    let request = %*{
      "query": "search for similar code",
      "maxResults": 5,
      "model": SimilarityEmbeddingModel,
      "indexPath": testIndexPath
    }
    
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let response = client.post(baseUrl & "/search/embedding", body = $request)
    
    # Accept either success or 500 (service unavailable)
    check response.code in [Http200, Http500]
    
    if response.code == Http200:
      let jsonResponse = parseJson(response.body)
      check jsonResponse.hasKey("results")
      check jsonResponse.hasKey("totalResults")
      check jsonResponse["results"].kind == JArray
      check jsonResponse["totalResults"].kind == JInt
    else:
      # 500 expected when embedding service is not available
      let jsonResponse = parseJson(response.body)
      check jsonResponse.hasKey("error")
      check jsonResponse["error"].kind == JString

  test "Embedding search with missing index file":
    ## Test that embedding search returns 400 error for missing index files.
    let request = %*{
      "query": "test query",
      "maxResults": 5,
      "model": SimilarityEmbeddingModel,
      "indexPath": "./nonexistent.flat"
    }
    
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let response = client.post(baseUrl & "/search/embedding", body = $request)
    
    check response.code == Http400
    
    let jsonResponse = parseJson(response.body)
    check jsonResponse["error"].getStr().contains("Index file not found")
    check jsonResponse["code"].getInt() == 400

  test "Invalid HTTP methods return 405":
    ## Test that invalid HTTP methods return proper 405 Method Not Allowed errors.
    # Test invalid method on ripgrep endpoint
    let response1 = client.get(baseUrl & "/search/ripgrep")
    check response1.code == Http405
    
    let jsonResponse1 = parseJson(response1.body)
    check jsonResponse1["error"].getStr() == "Method not allowed"
    check jsonResponse1["code"].getInt() == 405
    
    # Test invalid method on embedding endpoint
    let response2 = client.get(baseUrl & "/search/embedding")
    check response2.code == Http405
    
    # Test invalid method on openapi endpoint
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let response3 = client.post(baseUrl & "/openapi.json", body = "{}")
    check response3.code == Http405

  test "Unknown endpoints return 404":
    ## Test that requests to unknown endpoints return 404 Not Found.
    let response = client.get(baseUrl & "/unknown/endpoint")
    
    check response.code == Http404
    
    let jsonResponse = parseJson(response.body)
    check jsonResponse["error"].getStr().contains("Endpoint not found")
    check jsonResponse["code"].getInt() == 404

  test "CORS headers are present":
    ## Test that all responses include proper CORS headers for web compatibility.
    let response = client.get(baseUrl & "/")
    
    check response.headers.hasKey("Access-Control-Allow-Origin")
    check response.headers["Access-Control-Allow-Origin"] == "*"
    check response.headers.hasKey("Access-Control-Allow-Methods")
    check response.headers.hasKey("Access-Control-Allow-Headers")

  test "OPTIONS requests handled correctly":
    ## Test that preflight OPTIONS requests are handled correctly.
    let response = client.request(baseUrl & "/search/ripgrep", HttpOptions)
    
    check response.code == Http200
    check response.headers.hasKey("Access-Control-Allow-Origin")
    check response.headers["Access-Control-Allow-Origin"] == "*"

when isMainModule:
  discard 
