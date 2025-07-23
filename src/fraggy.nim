## Fraggy CLI - Document fragment and AI indexing tool

import
  std/[strutils, strformat, os, algorithm],
  ./types, ./configs, ./index, ./search, ./openapi

# re-export our internal modules for convenience
export types, configs, index, search, openapi

# flatty is used to serialize/deserialize to flat files
# top level organization is a git repo, eg monofuel/fragg or monolab/racha
# each repo has many files
# each file has many fragments
# each fragment has a line start, end, and an embedding vector

# nomic-embed-text is used for similarity search with local embeddings and ollama.

# the index flatfiles will be saved at ~/.fraggy/{git_owner}/{git_repo}/{embedding_model_name}.flat
# multiple embedding models may be used for a single repo, and kept in separate files.

## File Fragments may or may not overlap
## a simple implementation could just chunk the file on lines
## a more sophisticated fragmenter could index on boundaries for the file type. eg: functions in a program, headers in markdown, etc.
## an even more sophisticated fragmenter could have both large and small overlapping fragments to help cover a broad range of embeddings.

proc printHelp*() =
  ## Print help information for fraggy commands.
  echo "Usage: fraggy <command> [options]"
  echo ""
  echo "Configuration Commands:"
  echo "  --add-folder-index <path>   Add folder to tracking config"
  echo "  --add-repo-index <path>     Add git repository to tracking config"
  echo "  --show-config               Show current configuration"
  echo "  --index-all                 Index all configured folders and repos"
  echo ""
  echo "Server Commands:"
  echo "  --server [port] [address]   Start OpenAPI server (default: 8080, localhost)"
  echo ""
  echo "Search Commands:"
  echo "  -r, --ripgrep-search <pattern> [options]"
  echo "    Options: --case-insensitive --max-results=N"
  echo "  -e, --embedding-search <query> [options]"
  echo "    Options: --max-results=N --model=MODEL"
  echo ""
  echo "Note: Search commands automatically find and search all available indexes."
  echo "Use --index-all to create/update indexes before searching."
  echo ""
  echo "Other:"
  echo "  help                        Show this help message"

proc findAllIndexes*(): seq[string] =
  ## Find all available index files from configured folders and repos.
  result = @[]
  
  let fraggyDir = getHomeDir() / ".fraggy"
  
  # Find folder indexes
  let foldersDir = fraggyDir / "folders"
  if dirExists(foldersDir):
    for file in walkDir(foldersDir):
      if file.kind == pcFile and file.path.endsWith(".flat"):
        result.add(file.path)
  
  # Find repo indexes
  let reposDir = fraggyDir / "repos"
  if dirExists(reposDir):
    for file in walkDir(reposDir):
      if file.kind == pcFile and file.path.endsWith(".flat"):
        result.add(file.path)
  
  if result.len == 0:
    echo "No indexes found. Run 'fraggy --index-all' first to create indexes."

proc performRipgrepSearch*(args: seq[string]) =
  ## Perform a ripgrep search from command line arguments.
  if args.len < 2:
    echo "Error: ripgrep search requires a search pattern"
    echo "Usage: fraggy -r <pattern> [--case-insensitive] [--max-results=N]"
    echo "   or: fraggy --ripgrep-search <pattern> [options]"
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
        echo "Warning: Invalid max-results value, using default: 100"
  
  let indexPaths = findAllIndexes()
  if indexPaths.len == 0:
    return
  
  echo &"Searching for pattern: '{pattern}'"
  echo &"Case sensitive: {caseSensitive}, Max results: {maxResults}"
  echo &"Searching across {indexPaths.len} indexes..."
  echo "---"
  
  var allResults: seq[RipgrepResult] = @[]
  
  for indexPath in indexPaths:
    try:
      let index = readIndexFromFile(indexPath)
      let results = ripgrepSearch(index, pattern, caseSensitive, maxResults)
      allResults.add(results)
    except Exception as e:
      echo &"Warning: Could not search index {extractFilename(indexPath)}: {e.msg}"
  
  # Sort all results by relevance/file name
  allResults.sort do (a, b: RipgrepResult) -> int:
    cmp(a.file.filename, b.file.filename)
  
  # Limit to max results
  if allResults.len > maxResults:
    allResults = allResults[0..<maxResults]
  
  if allResults.len == 0:
    echo "No matches found."
    return
  
  echo &"Found {allResults.len} results:"
  echo ""
  
  for i, result in allResults:
    echo &"[{i+1}] {result.file.filename}:{result.lineNumber}"
    echo &"    {result.lineContent}"
    echo &"    Match at columns {result.matchStart}-{result.matchEnd}"
    echo ""

proc performEmbeddingSearch*(args: seq[string]) =
  ## Perform an embedding search from command line arguments.
  if args.len < 2:
    echo "Error: embedding search requires a search query"
    echo "Usage: fraggy -e <query> [--max-results=N] [--model=MODEL]"
    echo "   or: fraggy --embedding-search <query> [options]"
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
        echo "Warning: Invalid max-results value, using default: 10"
    elif args[i].startsWith("--model="):
      model = args[i].split("=")[1]
  
  let indexPaths = findAllIndexes()
  if indexPaths.len == 0:
    return
  
  echo &"Searching for: '{query}'"
  echo &"Model: {model}, Max results: {maxResults}"
  echo &"Searching across {indexPaths.len} indexes..."
  echo "---"
  
  var allResults: seq[SimilarityResult] = @[]
  
  for indexPath in indexPaths:
    try:
      let index = readIndexFromFile(indexPath)
      let results = findSimilarFragments(index, query, maxResults, model)
      allResults.add(results)
    except Exception as e:
      echo &"Warning: Could not search index {extractFilename(indexPath)}: {e.msg}"
  
  # Sort all results by similarity score (highest first)
  allResults.sort do (a, b: SimilarityResult) -> int:
    cmp(b.similarity, a.similarity)
  
  # Limit to max results
  if allResults.len > maxResults:
    allResults = allResults[0..<maxResults]
  
  if allResults.len == 0:
    echo "No similar fragments found."
    return
  
  echo &"Found {allResults.len} similar fragments:"
  echo ""
  
  for i, result in allResults:
    echo &"[{i+1}] {result.file.filename} (similarity: {result.similarity:.3f})"
    echo &"    Lines {result.fragment.startLine}-{result.fragment.endLine}"
    echo &"    Type: {result.fragment.fragmentType}"
    echo &"    Score: {result.fragment.contentScore}"
    echo ""

proc startApiServer*(args: seq[string]) =
  ## Start the OpenAPI server with optional port and address.
  var port = 8080
  var address = "localhost"
  
  # Parse optional port and address
  if args.len > 1:
    try:
      port = parseInt(args[1])
    except:
      echo "Warning: Invalid port number, using default: 8080"
  
  if args.len > 2:
    address = args[2]
  
  echo &"Starting Fraggy OpenAPI server on {address}:{port}"
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
      echo "Error: --add-folder-index requires a path argument"
      printHelp()
      return
    addFolderToConfig(args[1])
  of "--add-repo-index":
    if args.len < 2:
      echo "Error: --add-repo-index requires a path argument"
      printHelp()
      return
    addGitRepoToConfig(args[1])
  of "--show-config":
    showConfig()
  of "--index-all":
    indexAll()
  of "--server":
    startApiServer(args)
  of "-r", "--ripgrep-search":
    performRipgrepSearch(args)
  of "-e", "--embedding-search":
    performEmbeddingSearch(args)
  else:
    echo &"Unknown command: {cmd}"
    echo ""
    printHelp()

when isMainModule:
  main()