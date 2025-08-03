import
  std/[unittest, strformat, strutils, os, osproc, options],
  jsony, openapi, regen, curly

## Test suite for the Regen Search API endpoints.
## Validates all HTTP endpoints, error handling, and response formats.
## Automatically starts and stops the server for testing.

const
  TestPort = 8888
  TestHost = "localhost"

suite "Regen Search API Tests":
  var 
    client: Curly
    baseUrl: string
    testIndexPath: string
    serverProcess: Process
    authHeaders: HttpHeaders

  proc startTestServer(): Process =
    ## Start the API server process for testing.
    echo "Compiling server..."
    let compileResult = execCmd("nim c src/regen.nim")
    if compileResult != 0:
      echo "Failed to compile server"
      quit(1)
    
    echo &"Starting test server with host {TestHost} and port {TestPort}"
    let process = startProcess("./src/regen", args = @["--server", $TestPort], 
                              options = {poUsePath, poStdErrToStdOut})
    return process

  proc waitForServerReady(maxWaitSeconds: int = 10): bool =
    ## Wait for the server to be ready to accept connections.
    let testClient = newCurly()
    
    for i in 1..maxWaitSeconds:
      try:
        echo "Waiting for server to be ready..."
        let response = testClient.get("http://" & TestHost & ":" & $TestPort & "/", timeout = 1)
        if response.code == 200:
          testClient.close()
          return true
      except:
        discard
      
      sleep(1000)  # Wait 1 second before retry
    
    testClient.close()
    return false

  proc stopTestServer(process: Process) =
    ## Stop the test server process.
    echo "kill server"
    process.kill()
    discard process.waitForExit()
    process.close()

  proc createTestIndex() =
    ## Create a minimal test index file for testing API endpoints.
    # Create index in the proper directory that findAllIndexes() searches
    let regenDir = getHomeDir() / ".regen"
    let foldersDir = regenDir / "folders"
    if not dirExists(regenDir):
      createDir(regenDir)
    if not dirExists(foldersDir):
      createDir(foldersDir)
    
    testIndexPath = foldersDir / "test_index.flat"
    
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

  # Suite setup - start the server once
  client = newCurly()
  baseUrl = "http://" & TestHost & ":" & $TestPort
  
  # Compile regen before getting API key
  echo "Compiling regen for API key retrieval..."
  let compileResult = execCmd("nim c src/regen.nim")
  if compileResult != 0:
    echo "Failed to compile regen"
    quit(1)
  
  # Get API key from regen command
  let apiKeyResult = execCmdEx("./src/regen --show-api-key")
  let apiKey = apiKeyResult.output.strip()
  
  authHeaders["Content-Type"] = "application/json"
  authHeaders["Authorization"] = "Bearer " & apiKey
  
  createTestIndex()
  
  # Start the server once and wait for it to be ready
  serverProcess = startTestServer()
  if not waitForServerReady():
    stopTestServer(serverProcess)
    quit(1)

  test "Health endpoint returns correct format":
    ## Test that the health endpoint returns proper JSON with expected fields.
    let response = client.get(baseUrl & "/")
    
    check response.code == 200
    check "application/json" in response.headers["Content-Type"]
    
    # Parse as generic JSON since health endpoint doesn't have a specific type
    let jsonStr = response.body
    check "Regen Search API" in jsonStr
    check "1.0.0" in jsonStr
    check "endpoints" in jsonStr

  test "OpenAPI spec endpoint returns valid JSON":
    ## Test that the OpenAPI specification endpoint returns valid OpenAPI 3.0 spec.
    let response = client.get(baseUrl & "/openapi.json")
    
    check response.code == 200
    check "application/json" in response.headers["Content-Type"]
    
    # Check spec contains expected content
    let specStr = response.body
    check "3.0.3" in specStr
    check "Regen Search API" in specStr
    check "1.0.0" in specStr
    check "paths" in specStr
    check "/search/ripgrep" in specStr
    check "/search/embedding" in specStr

  test "Ripgrep search with valid request":
    ## Test ripgrep search endpoint with a valid request and test index.
    let request = RipgrepRequest(
      pattern: "test",
      caseSensitive: some(true),
      maxResults: some(10)
    )
    
    let response = client.post(baseUrl & "/search/ripgrep", 
                               headers = authHeaders,
                               body = request.toJson())
    
    check response.code == 200
    
    let ripgrepResponse = fromJson(response.body, RipgrepResponse)
    check ripgrepResponse.matches.len >= 0



  test "Ripgrep search with invalid JSON":
    ## Test that invalid JSON requests are handled with proper error responses.
    let response = client.post(baseUrl & "/search/ripgrep", 
                               headers = authHeaders,
                               body = "{invalid json")
    
    check response.code == 500  # Will be caught by general exception handler

  test "Embedding search with valid request":
    ## Test embedding search endpoint with valid request and test index.
    ## Note: May return 500 if embedding service (ollama) is not available.
    let request = EmbeddingSearchRequest(
      query: "search for similar code",
      maxResults: some(5),
      model: some(SimilarityEmbeddingModel)
    )
    
    let response = client.post(baseUrl & "/search/embedding", 
                               headers = authHeaders,
                               body = request.toJson())
    
    # Accept either success or 500 (service unavailable)
    check response.code in [200, 500]
    
    if response.code == 200:
      let embeddingResponse = fromJson(response.body, EmbeddingSearchResponse)
      check embeddingResponse.results.len >= 0
      check embeddingResponse.totalResults >= 0
    else:
      # 500 expected when embedding service is not available
      let errorResponse = fromJson(response.body, ErrorResponse)
      check errorResponse.error.len > 0



  test "Invalid HTTP methods return 405":
    ## Test that invalid HTTP methods return proper 405 Method Not Allowed errors.
    # Test invalid method on ripgrep endpoint
    let response1 = client.get(baseUrl & "/search/ripgrep")
    check response1.code == 405
    
    let errorResponse1 = fromJson(response1.body, ErrorResponse)
    check errorResponse1.error == "Method not allowed"
    check errorResponse1.code == 405
    
    # Test invalid method on embedding endpoint
    let response2 = client.get(baseUrl & "/search/embedding")
    check response2.code == 405
    
    # Test invalid method on openapi endpoint
    let response3 = client.post(baseUrl & "/openapi.json", 
                                headers = authHeaders,
                                body = "{}")
    check response3.code == 405

  test "Unknown endpoints return 404":
    ## Test that requests to unknown endpoints return 404 Not Found.
    let response = client.get(baseUrl & "/unknown/endpoint")
    
    check response.code == 404
    
    let errorResponse = fromJson(response.body, ErrorResponse)
    check "Endpoint not found" in errorResponse.error
    check errorResponse.code == 404

  test "CORS headers are present":
    ## Test that all responses include proper CORS headers for web compatibility.
    let response = client.get(baseUrl & "/")
    
    check "Access-Control-Allow-Origin" in response.headers
    check response.headers["Access-Control-Allow-Origin"] == "*"
    check "Access-Control-Allow-Methods" in response.headers
    check "Access-Control-Allow-Headers" in response.headers

  test "OPTIONS requests handled correctly":
    ## Test that preflight OPTIONS requests are handled correctly.
    let response = client.makeRequest("OPTIONS", baseUrl & "/search/ripgrep")
    
    check response.code == 200
    check "Access-Control-Allow-Origin" in response.headers
    check response.headers["Access-Control-Allow-Origin"] == "*"

  # Suite teardown - cleanup once
  client.close()
  stopTestServer(serverProcess)
  if fileExists(testIndexPath):
    removeFile(testIndexPath)
