## Regen CLI - Document fragment and AI indexing tool

import
  std/[strutils, strformat, os, algorithm],
  ./types, ./configs, ./index, ./search, ./openapi, ./logs

# re-export our internal modules for convenience
export types, configs, index, search, openapi

# flatty is used to serialize/deserialize to flat files
# top level organization is a git repo, eg monofuel/fragg or monolab/racha
# each repo has many files
# each file has many fragments
# each fragment has a line start, end, and an embedding vector

# nomic-embed-text is used for similarity search with local embeddings and ollama.

# the index flatfiles will be saved at ~/.regen/{git_owner}/{git_repo}/{embedding_model_name}.flat
# multiple embedding models may be used for a single repo, and kept in separate files.

## File Fragments may or may not overlap
## a simple implementation could just chunk the file on lines
## a more sophisticated fragmenter could index on boundaries for the file type. eg: functions in a program, headers in markdown, etc.
## an even more sophisticated fragmenter could have both large and small overlapping fragments to help cover a broad range of embeddings.

proc printHelp*() =
  ## Print help information for regen commands.
  info "Usage: regen <command> [options]"
  info ""
  info "Configuration Commands:"
  info "  --add-folder-index <path>   Add folder to tracking config"
  info "  --add-repo-index <path>     Add git repository to tracking config"
  info "  --show-config               Show current configuration"
  info "  --show-api-key              Show API key for Bearer authentication"
  info "  --index-all                 Index all configured folders and repos"
  info ""
  info "Server Commands:"
  info "  --server [port] [address]   Start OpenAPI server (default: 8080, localhost)"
  info ""
  info "Search Commands:"
  info "  -r, --ripgrep-search <pattern> [options]"
  info "    Options: --case-insensitive --max-results=N"
  info "  -e, --embedding-search <query> [options]"
  info "    Options: --max-results=N --model=MODEL"
  info ""
  info "Note: Search commands automatically find and search all available indexes."
  info "Use --index-all to create/update indexes before searching."
  info ""
  info "Other:"
  info "  help                        Show this help message"

proc extractFragmentContent*(file: RegenFile, fragment: RegenFragment): seq[string] =
  ## Extract the actual text content from a file fragment.
  result = @[]
  
  if not fileExists(file.path):
    return @[]
  
  let content = readFile(file.path)
  let lines = content.split('\n')
  
  # Extract lines from startLine to endLine (1-based indexing)
  let startIdx = max(0, fragment.startLine - 1)
  let endIdx = min(lines.len - 1, fragment.endLine - 1)
  
  for i in startIdx..endIdx:
    result.add(lines[i])

proc performRipgrepSearch*(args: seq[string]) =
  ## Perform a ripgrep search from command line arguments.
  if args.len < 2:
    error "ripgrep search requires a search pattern"
    info "Usage: regen -r <pattern> [--case-insensitive] [--max-results=N]"
    info "   or: regen --ripgrep-search <pattern> [options]"
    return
  
  let pattern = args[1]
  var caseSensitive = true
  var maxResults = 100
  
  # Parse optional arguments
  for i in 2..<args.len:
    if args[i] == "--case-insensitive":
      caseSensitive = false
    elif args[i].startsWith("--max-results="):
      try:
        maxResults = parseInt(args[i].split("=")[1])
      except:
        warn "Invalid max-results value, using default: 100"
  
  let indexPaths = findAllIndexes()
  if indexPaths.len == 0:
    return
  
  var allResults: seq[RipgrepResult] = @[]
  
  for indexPath in indexPaths:
    try:
      let index = readIndexFromFile(indexPath)
      let results = ripgrepSearch(index, pattern, caseSensitive, maxResults)
      allResults.add(results)
    except Exception as e:
      warn &"Could not search index {extractFilename(indexPath)}: {e.msg}"
  
  # Sort all results by filename then line number (like ripgrep)
  allResults.sort do (a, b: RipgrepResult) -> int:
    let fileCompare = cmp(a.file.filename, b.file.filename)
    if fileCompare != 0:
      fileCompare
    else:
      cmp(a.lineNumber, b.lineNumber)
  
  # Limit to max results
  if allResults.len > maxResults:
    allResults = allResults[0..<maxResults]
  
  # Group by filename and output in ripgrep format
  var currentFile = ""
  for result in allResults:
    if result.file.filename != currentFile:
      if currentFile != "":
        echo ""  # Blank line between files
      echo result.file.filename  # File header
      currentFile = result.file.filename
    echo &"{result.lineNumber}:{result.lineContent}"  # line_number:content

proc performEmbeddingSearch*(args: seq[string]) =
  ## Perform an embedding search from command line arguments.
  if args.len < 2:
    error "embedding search requires a search query"
    info "Usage: regen -e <query> [--max-results=N] [--model=MODEL]"
    info "   or: regen --embedding-search <query> [options]"
    return
  
  let query = args[1]
  var maxResults = 10
  var model = SimilarityEmbeddingModel
  
  # Parse optional arguments
  for i in 2..<args.len:
    if args[i].startsWith("--max-results="):
      try:
        maxResults = parseInt(args[i].split("=")[1])
      except:
        warn "Invalid max-results value, using default: 10"
    elif args[i].startsWith("--model="):
      model = args[i].split("=")[1]
  
  let indexPaths = findAllIndexes()
  if indexPaths.len == 0:
    return
  
  info &"Searching for: '{query}'"
  info &"Model: {model}, Max results: {maxResults}"
  info &"Searching across {indexPaths.len} indexes..."
  info "---"
  
  var allResults: seq[SimilarityResult] = @[]
  
  for indexPath in indexPaths:
    try:
      let index = readIndexFromFile(indexPath)
      let results = findSimilarFragments(index, query, maxResults, model)
      allResults.add(results)
    except Exception as e:
      warn &"Could not search index {extractFilename(indexPath)}: {e.msg}"
  
  # Sort all results by similarity score (highest first)
  allResults.sort do (a, b: SimilarityResult) -> int:
    cmp(b.similarity, a.similarity)
  
  # Limit to max results
  if allResults.len > maxResults:
    allResults = allResults[0..<maxResults]
  
  if allResults.len == 0:
    info "No similar fragments found."
    return
  
  info &"Found {allResults.len} similar fragments:"
  info ""
  
  # Group by filename and output in ripgrep-like format
  var currentFile = ""
  for i, result in allResults:
    if result.file.filename != currentFile:
      if currentFile != "":
        echo ""  # Blank line between files
      echo &"{result.file.filename} (similarity: {result.similarity:.3f})"
      currentFile = result.file.filename
    
    # Extract and display the actual fragment content
    let fragmentLines = extractFragmentContent(result.file, result.fragment)
    for lineIdx, lineContent in fragmentLines:
      let actualLineNum = result.fragment.startLine + lineIdx
      echo &"{actualLineNum}:{lineContent}"

proc startApiServer*(args: seq[string]) =
  ## Start the OpenAPI server with optional port and address.
  var port = 8095
  var address = "0.0.0.0"
  
  # Parse optional port and address
  if args.len > 1:
    try:
      port = parseInt(args[1])
    except:
      warn "Invalid port number, using default: 8080"
  
  if args.len > 2:
    address = args[2]
  
  info &"Starting Regen OpenAPI server on {address}:{port}"
  startServer(port, address)

proc main() =
  let args = commandLineParams()
  
  if args.len == 0 or (args.len > 0 and args[0] == "help"):
    printHelp()
    return
  
  let cmd = args[0]
  case cmd:
  of "--add-folder-index":
    if args.len < 2:
      error "--add-folder-index requires a path argument"
      printHelp()
      return
    addFolderToConfig(args[1])
  of "--add-repo-index":
    if args.len < 2:
      error "--add-repo-index requires a path argument"
      printHelp()
      return
    addGitRepoToConfig(args[1])
  of "--show-config":
    showConfig()
  of "--show-api-key":
    let config = loadConfig()
    echo config.apiKey
  of "--index-all":
    indexAll()
  of "--server":
    startApiServer(args)
  of "-r", "--ripgrep-search":
    performRipgrepSearch(args)
  of "-e", "--embedding-search":
    performEmbeddingSearch(args)
  else:
    error &"Unknown command: {cmd}"
    info ""
    printHelp()

when isMainModule:
  main()
