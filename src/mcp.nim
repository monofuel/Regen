## MCP server for Regen - exposes the same search functionality as the OpenAPI server via MCP tools.

import
  std/[json, strutils, strformat, algorithm, os],
  mcport,
  ./types, ./search, ./index, ./logs, ./configs

const
  McpServerName = "RegenMCPServer"
  McpServerVersion = "1.0.0"

proc buildRipgrepInputSchema(): JsonNode =
  ## Build JSON Schema for ripgrep_search tool input.
  %*{
    "type": "object",
    "properties": {
      "pattern": {"type": "string", "description": "The text pattern to search for"},
      "caseSensitive": {"type": "boolean", "default": true, "description": "Case sensitive search"},
      "maxResults": {"type": "integer", "default": 100, "description": "Maximum number of results"}
    },
    "required": ["pattern"],
    "additionalProperties": false,
    "$schema": "http://json-schema.org/draft-07/schema#"
  }

proc buildEmbeddingInputSchema(): JsonNode =
  ## Build JSON Schema for embedding_search tool input.
  %*{
    "type": "object",
    "properties": {
      "query": {"type": "string", "description": "Semantic query"},
      "maxResults": {"type": "integer", "default": 10, "description": "Maximum number of results"},
      "model": {"type": "string", "default": "nomic-embed-text", "description": "Embedding model"}
    },
    "required": ["query"],
    "additionalProperties": false,
    "$schema": "http://json-schema.org/draft-07/schema#"
  }

proc extractFragmentContent(file: RegenFile, fragment: RegenFragment): seq[JsonNode] =
  ## Extract the actual text content from a file fragment with line numbers for responses.
  result = @[]
  if not fileExists(file.path):
    return @[]
  let content = readFile(file.path)
  let lines = content.split('\n')
  let startIdx = max(0, fragment.startLine - 1)
  let endIdx = min(lines.len - 1, fragment.endLine - 1)
  for i in startIdx..endIdx:
    let actualLineNum = fragment.startLine + (i - startIdx)
    result.add(%*{
      "lineNumber": actualLineNum,
      "content": lines[i]
    })

proc registerRegenTools(server: McpServer) =
  ## Register Regen search tools on the MCP server.
  # ripgrep_search tool
  let ripgrepTool = McpTool(
    name: "ripgrep_search",
    description: "Search files using ripgrep across all configured indexes",
    inputSchema: buildRipgrepInputSchema()
  )

  proc ripgrepHandler(arguments: JsonNode): JsonNode {.gcsafe.} =
    let hasPattern = arguments.hasKey("pattern") and arguments["pattern"].kind == JString
    if not hasPattern:
      raise newException(CatchableError, "'pattern' is required and must be a string")
    let pattern = arguments["pattern"].getStr()
    let caseSensitive = if arguments.hasKey("caseSensitive"): arguments["caseSensitive"].getBool() else: true
    var maxResults = 100
    if arguments.hasKey("maxResults"):
      try:
        maxResults = arguments["maxResults"].getInt()
      except:
        discard

    let indexPaths = findAllIndexes()
    if indexPaths.len == 0:
      raise newException(CatchableError, "No indexes found. Run 'regen --index-all' first to create indexes.")

    var allResults: seq[RipgrepResult] = @[]
    for indexPath in indexPaths:
      try:
        let idx = readIndexFromFile(indexPath)
        let results = ripgrepSearch(idx, pattern, caseSensitive, maxResults)
        allResults.add(results)
      except Exception as e:
        warn &"Could not search index {extractFilename(indexPath)}: {e.msg}"

    allResults.sort do (a, b: RipgrepResult) -> int:
      let fileCompare = cmp(a.file.filename, b.file.filename)
      if fileCompare != 0:
        fileCompare
      else:
        cmp(a.lineNumber, b.lineNumber)

    if allResults.len > maxResults:
      allResults = allResults[0..<maxResults]

    var matches: seq[JsonNode] = @[]
    for r in allResults:
      matches.add(%*{
        "path": r.file.filename,
        "line_number": r.lineNumber,
        "line": r.lineContent,
        "match_start": r.matchStart,
        "match_end": r.matchEnd
      })

    %*{"matches": matches}

  server.registerTool(ripgrepTool, ripgrepHandler)

  # embedding_search tool
  let embeddingTool = McpTool(
    name: "embedding_search",
    description: "Semantic similarity search using AI embeddings across all configured indexes",
    inputSchema: buildEmbeddingInputSchema()
  )

  proc embeddingHandler(arguments: JsonNode): JsonNode {.gcsafe.} =
    let hasQuery = arguments.hasKey("query") and arguments["query"].kind == JString
    if not hasQuery:
      raise newException(CatchableError, "'query' is required and must be a string")
    let query = arguments["query"].getStr()
    var maxResults = 10
    if arguments.hasKey("maxResults"):
      try:
        maxResults = arguments["maxResults"].getInt()
      except:
        discard
    let model = if arguments.hasKey("model"): arguments["model"].getStr() else: "nomic-embed-text"

    let indexPaths = findAllIndexes()
    if indexPaths.len == 0:
      raise newException(CatchableError, "No indexes found. Run 'regen --index-all' first to create indexes.")

    var allResults: seq[SimilarityResult] = @[]
    for indexPath in indexPaths:
      try:
        let idx = readIndexFromFile(indexPath)
        let results = findSimilarFragments(idx, query, maxResults, model)
        allResults.add(results)
      except Exception as e:
        warn &"Could not search index {extractFilename(indexPath)}: {e.msg}"

    allResults.sort do (a, b: SimilarityResult) -> int:
      cmp(b.similarity, a.similarity)

    if allResults.len > maxResults:
      allResults = allResults[0..<maxResults]

    var apiResults: seq[JsonNode] = @[]
    for res in allResults:
      let lines = extractFragmentContent(res.file, res.fragment)
      apiResults.add(%*{
        "file": {
          "path": res.file.path,
          "filename": res.file.filename,
          "hash": res.file.hash
        },
        "fragment": {
          "startLine": res.fragment.startLine,
          "endLine": res.fragment.endLine,
          "fragmentType": res.fragment.fragmentType,
          "contentScore": res.fragment.contentScore
        },
        "similarity": res.similarity,
        "lines": lines
      })

    %*{
      "results": apiResults,
      "totalResults": apiResults.len
    }

  server.registerTool(embeddingTool, embeddingHandler)

proc startMcpHttpServer*(args: seq[string]) =
  ## Start the MCP HTTP server with optional port and address.
  var port = 8096
  var address = "0.0.0.0"

  if args.len > 1:
    try:
      port = parseInt(args[1])
    except:
      warn "Invalid port number, using default: 8096"
  if args.len > 2:
    address = args[2]

  discard loadConfig()
  info &"Starting Regen MCP HTTP server on {address}:{port}"

  let mcpServer = newMcpServer(McpServerName, McpServerVersion)
  registerRegenTools(mcpServer)

  let httpServer = newHttpMcpServer(mcpServer, true)
  httpServer.serve(port, address)
