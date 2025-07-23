## OpenAPI server for Fraggy search functionality

import
  std/[strutils, os, json, sequtils, strformat, algorithm],
  mummy, jsony,
  ./types, ./search, ./index, ./logs

# Request/Response types for API endpoints
type
  RipgrepRequest* = object
    pattern*: string
    caseSensitive*: bool
    maxResults*: int
    indexPath*: string

  EmbeddingSearchRequest* = object
    query*: string
    maxResults*: int
    model*: string
    indexPath*: string

  # Simplified ripgrep-like response format
  RipgrepResponse* = object
    matches*: seq[RipgrepMatch]

  RipgrepMatch* = object
    path*: string
    line_number*: int
    line*: string
    match_start*: int
    match_end*: int

  EmbeddingSearchResponse* = object
    results*: seq[SimilarityResultApi]
    totalResults*: int

  SimilarityResultApi* = object
    file*: FileInfo
    fragment*: FragmentInfo
    similarity*: float32
    lines*: seq[LineContent]

  FileInfo* = object
    path*: string
    filename*: string
    hash*: string

  FragmentInfo* = object
    startLine*: int
    endLine*: int
    fragmentType*: string
    contentScore*: int

  LineContent* = object
    lineNumber*: int
    content*: string

  ErrorResponse* = object
    error*: string
    code*: int

# Helper function to extract fragment content (similar to fraggy.nim)
proc extractFragmentContent*(file: FraggyFile, fragment: FraggyFragment): seq[LineContent] =
  ## Extract the actual text content from a file fragment with line numbers.
  result = @[]
  
  if not fileExists(file.path):
    return @[]
  
  let content = readFile(file.path)
  let lines = content.split('\n')
  
  # Extract lines from startLine to endLine (1-based indexing)
  let startIdx = max(0, fragment.startLine - 1)
  let endIdx = min(lines.len - 1, fragment.endLine - 1)
  
  for i in startIdx..endIdx:
    let actualLineNum = fragment.startLine + (i - startIdx)
    result.add(LineContent(
      lineNumber: actualLineNum,
      content: lines[i]
    ))

# Helper functions for converting fraggy types to API types
proc toRipgrepMatch*(ripgrepResult: RipgrepResult): RipgrepMatch =
  RipgrepMatch(
    path: ripgrepResult.file.filename,
    line_number: ripgrepResult.lineNumber,
    line: ripgrepResult.lineContent,
    match_start: ripgrepResult.matchStart,
    match_end: ripgrepResult.matchEnd
  )

proc toFileInfo*(fraggyFile: FraggyFile): FileInfo =
  FileInfo(
    path: fraggyFile.path,
    filename: fraggyFile.filename,
    hash: fraggyFile.hash
  )

proc toFragmentInfo*(fragment: FraggyFragment): FragmentInfo =
  FragmentInfo(
    startLine: fragment.startLine,
    endLine: fragment.endLine,
    fragmentType: fragment.fragmentType,
    contentScore: fragment.contentScore
  )

proc toSimilarityResultApi*(simResult: SimilarityResult): SimilarityResultApi =
  let lines = extractFragmentContent(simResult.file, simResult.fragment)
  SimilarityResultApi(
    file: simResult.file.toFileInfo(),
    fragment: simResult.fragment.toFragmentInfo(),
    similarity: simResult.similarity,
    lines: lines
  )

# API endpoint handlers
proc handleRipgrepSearch*(request: Request) =
  try:
    let reqData = fromJson(request.body, RipgrepRequest)
    
    if not fileExists(reqData.indexPath):
      request.respond(400, body = ErrorResponse(
        error: "Index file not found: " & reqData.indexPath,
        code: 400
      ).toJson())
      return
    
    let index = readIndexFromFile(reqData.indexPath)
    let results = ripgrepSearch(index, reqData.pattern, reqData.caseSensitive, reqData.maxResults)
    
    # Sort results like ripgrep (by filename then line number)
    let sortedResults = results.sorted do (a, b: RipgrepResult) -> int:
      let fileCompare = cmp(a.file.filename, b.file.filename)
      if fileCompare != 0:
        fileCompare
      else:
        cmp(a.lineNumber, b.lineNumber)
    
    let matches = sortedResults.map(toRipgrepMatch)
    let response = RipgrepResponse(matches: matches)
    
    request.respond(200, body = response.toJson())
    
  except Exception as e:
    request.respond(500, body = ErrorResponse(
      error: "Error: " & e.msg,
      code: 500
    ).toJson())

proc handleEmbeddingSearch*(request: Request) =
  try:
    let reqData = fromJson(request.body, EmbeddingSearchRequest)
    
    if not fileExists(reqData.indexPath):
      request.respond(400, body = ErrorResponse(
        error: "Index file not found: " & reqData.indexPath,
        code: 400
      ).toJson())
      return
    
    let index = readIndexFromFile(reqData.indexPath)
    let results = findSimilarFragments(index, reqData.query, reqData.maxResults, reqData.model)
    
    let apiResults = results.map(toSimilarityResultApi)
    let response = EmbeddingSearchResponse(
      results: apiResults,
      totalResults: apiResults.len
    )
    
    request.respond(200, body = response.toJson())
    
  except Exception as e:
    request.respond(500, body = ErrorResponse(
      error: "Error: " & e.msg,
      code: 500
    ).toJson())

# OpenAPI spec building functions
proc buildBaseSpec*(): JsonNode =
  ## Build the base OpenAPI specification info
  result = %*{
    "openapi": "3.0.3",
    "info": {
      "title": "Fraggy Search API",
      "description": "API for searching code using ripgrep and semantic embeddings",
      "version": "1.0.0"
    },
    "servers": [
      {
        "url": "http://localhost:8080",
        "description": "Local development server"
      }
    ]
  }

proc buildRipgrepSearchSpec*(): JsonNode =
  ## Build the OpenAPI spec for the ripgrep search endpoint
  result = %*{
    "post": {
      "summary": "Search files using ripgrep",
      "description": "Perform exact text search using ripgrep with optional case sensitivity",
      "requestBody": {
        "required": true,
        "content": {
          "application/json": {
            "schema": {
              "type": "object",
              "required": ["pattern", "indexPath"],
              "properties": {
                "pattern": {
                  "type": "string",
                  "description": "The text pattern to search for"
                },
                "caseSensitive": {
                  "type": "boolean", 
                  "default": true,
                  "description": "Whether the search should be case sensitive"
                },
                "maxResults": {
                  "type": "integer", 
                  "default": 100,
                  "description": "Maximum number of results to return"
                },
                "indexPath": {
                  "type": "string",
                  "description": "Path to the Fraggy index file"
                }
              }
            }
          }
        }
      },
      "responses": {
        "200": {
          "description": "Search results",
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "matches": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "path": {"type": "string"},
                        "line_number": {"type": "integer"},
                        "line": {"type": "string"},
                        "match_start": {"type": "integer"},
                        "match_end": {"type": "integer"}
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "400": {"description": "Bad request - invalid parameters"},
        "500": {"description": "Internal server error"}
      }
    }
  }

proc buildEmbeddingSearchSpec*(): JsonNode =
  ## Build the OpenAPI spec for the embedding search endpoint
  result = %*{
    "post": {
      "summary": "Search using semantic embeddings",
      "description": "Perform semantic similarity search using AI embeddings",
      "requestBody": {
        "required": true,
        "content": {
          "application/json": {
            "schema": {
              "type": "object",
              "required": ["query", "indexPath"],
              "properties": {
                "query": {
                  "type": "string",
                  "description": "The semantic query to search for"
                },
                "maxResults": {
                  "type": "integer", 
                  "default": 10,
                  "description": "Maximum number of results to return"
                },
                "model": {
                  "type": "string", 
                  "default": "nomic-embed-text",
                  "description": "The embedding model to use for search"
                },
                "indexPath": {
                  "type": "string",
                  "description": "Path to the Fraggy index file"
                }
              }
            }
          }
        }
      },
      "responses": {
        "200": {
          "description": "Search results",
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "results": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "file": {
                          "type": "object",
                          "properties": {
                            "path": {"type": "string"},
                            "filename": {"type": "string"},
                            "hash": {"type": "string"}
                          }
                        },
                        "fragment": {
                          "type": "object",
                          "properties": {
                            "startLine": {"type": "integer"},
                            "endLine": {"type": "integer"},
                            "fragmentType": {"type": "string"},
                            "contentScore": {"type": "integer"}
                          }
                        },
                        "similarity": {"type": "number", "format": "float"},
                        "lines": {
                          "type": "array",
                          "description": "Actual line content from the fragment",
                          "items": {
                            "type": "object",
                            "properties": {
                              "lineNumber": {"type": "integer"},
                              "content": {"type": "string"}
                            }
                          }
                        }
                      }
                    }
                  },
                  "totalResults": {"type": "integer"}
                }
              }
            }
          }
        },
        "400": {"description": "Bad request - invalid parameters"},
        "500": {"description": "Internal server error"}
      }
    }
  }

proc buildOpenApiSpecEndpointSpec*(): JsonNode =
  ## Build the OpenAPI spec for the spec endpoint itself
  result = %*{
    "get": {
      "summary": "Get OpenAPI specification",
      "description": "Returns the complete OpenAPI specification for this API",
      "responses": {
        "200": {
          "description": "OpenAPI specification",
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "description": "OpenAPI 3.0.3 specification"
              }
            }
          }
        },
        "500": {"description": "Internal server error"}
      }
    }
  }

proc buildHealthCheckSpec*(): JsonNode =
  ## Build the OpenAPI spec for the health check endpoint
  result = %*{
    "get": {
      "summary": "Health check and API information",
      "description": "Returns basic API information and available endpoints",
      "responses": {
        "200": {
          "description": "API information",
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "message": {"type": "string"},
                  "version": {"type": "string"},
                  "endpoints": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "path": {"type": "string"},
                        "method": {"type": "string"}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

proc buildCompleteOpenApiSpec*(): JsonNode =
  ## Assemble the complete OpenAPI specification by combining all endpoint specs
  result = buildBaseSpec()
  
  # Add the paths section by combining all endpoint specs
  result["paths"] = %*{
    "/search/ripgrep": buildRipgrepSearchSpec(),
    "/search/embedding": buildEmbeddingSearchSpec(),
    "/openapi.json": buildOpenApiSpecEndpointSpec(),
    "/": buildHealthCheckSpec()
  }

proc handleOpenApiSpec*(request: Request) =
  ## Handle requests for the OpenAPI specification
  try:
    let spec = buildCompleteOpenApiSpec()
    var headers: HttpHeaders
    headers["Content-Type"] = "application/json"
    request.respond(200, headers, body = $spec)
  except Exception as e:
    request.respond(500, body = ErrorResponse(
      error: "Failed to generate spec: " & e.msg,
      code: 500
    ).toJson())

# Main router
proc router*(request: Request) =
  let path = request.path
  
  # Set CORS headers for all responses
  var headers: HttpHeaders
  headers["Access-Control-Allow-Origin"] = "*"
  headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
  headers["Access-Control-Allow-Headers"] = "Content-Type"
  headers["Content-Type"] = "application/json"
  
  # Handle preflight requests
  if request.httpMethod == "OPTIONS":
    request.respond(200, headers)
    return
  
  case path:
  of "/search/ripgrep":
    if request.httpMethod == "POST":
      handleRipgrepSearch(request)
    else:
      request.respond(405, headers, body = ErrorResponse(
        error: "Method not allowed",
        code: 405
      ).toJson())
  
  of "/search/embedding":
    if request.httpMethod == "POST":
      handleEmbeddingSearch(request)
    else:
      request.respond(405, headers, body = ErrorResponse(
        error: "Method not allowed", 
        code: 405
      ).toJson())
  
  of "/openapi.json":
    if request.httpMethod == "GET":
      handleOpenApiSpec(request)
    else:
      request.respond(405, headers, body = ErrorResponse(
        error: "Method not allowed",
        code: 405
      ).toJson())
  
  of "/":
    # Simple health check / welcome message
    let welcomeMsg = %*{
      "openapi": "3.0.3",
      "message": "Fraggy Search API",
      "version": "1.0.0",
      "endpoints": [
        {"path": "/search/ripgrep", "method": "POST"},
        {"path": "/search/embedding", "method": "POST"},
        {"path": "/openapi.json", "method": "GET"}
      ]
    }
    request.respond(200, headers, body = $welcomeMsg)
  
  else:
    request.respond(404, headers, body = ErrorResponse(
      error: "Endpoint not found: " & path,
      code: 404
    ).toJson())

# Server startup
proc startServer*(port: int = 8080, address: string = "localhost") =
  info &"Starting Fraggy Search API server on {address}:{port}"
  info &"OpenAPI spec available at: http://{address}:{port}/openapi.json"
  
  let server = newServer(router)
  server.serve(Port(port), address) 