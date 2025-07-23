## Fraggy CLI - Document fragment and AI indexing tool

import
  std/[strutils, strformat, os],
  ./types, ./config, ./index, ./search, ./openapi

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
  echo "  --ripgrep-search <pattern> <index-path> [options]"
  echo "    Options: --case-insensitive --max-results=N"
  echo "  --embedding-search <query> <index-path> [options]"
  echo "    Options: --max-results=N --model=MODEL"
  echo ""
  echo "Other:"
  echo "  help                        Show this help message"

proc indexAll*() =
  ## Index all configured folders and git repositories.
  let config = loadConfig()
  
  echo "Indexing all configured paths..."
  
  # Index folders
  for folderPath in config.folders:
    if dirExists(folderPath):
      echo &"Indexing folder: {folderPath}"
      let folder = newFraggyFolder(folderPath, config.extensions)
      let index = FraggyIndex(version: ConfigVersion, kind: fraggy_folder, folder: folder)
      
      # Save index to ~/.fraggy/folders/{hash}.flat
      let folderHash = createFileHash(folderPath)
      let indexPath = getHomeDir() / ".fraggy" / "folders" / &"{folderHash}.flat"
      createDir(parentDir(indexPath))
      writeIndexToFile(index, indexPath)
      echo &"  Saved index to: {indexPath}"
    else:
      echo &"Warning: Folder does not exist: {folderPath}"
  
  # Index git repos
  for repoPath in config.gitRepos:
    if dirExists(repoPath):
      echo &"Indexing git repo: {repoPath}"
      let repo = newFraggyGitRepo(repoPath, config.extensions)
      let index = FraggyIndex(version: ConfigVersion, kind: fraggy_git_repo, repo: repo)
      
      # Save index to ~/.fraggy/repos/{repo_name}_{commit_hash}.flat
      let repoName = extractFilename(repoPath)
      let commitHash = getGitCommitHash(repoPath)
      let indexPath = getHomeDir() / ".fraggy" / "repos" / &"{repoName}_{commitHash}.flat"
      createDir(parentDir(indexPath))
      writeIndexToFile(index, indexPath)
      echo &"  Saved index to: {indexPath}"
    else:
      echo &"Warning: Git repo does not exist: {repoPath}"

proc performRipgrepSearch*(args: seq[string]) =
  ## Perform a ripgrep search from command line arguments.
  if args.len < 3:
    echo "Error: --ripgrep-search requires pattern and index-path"
    echo "Usage: fraggy --ripgrep-search <pattern> <index-path> [--case-insensitive] [--max-results=N]"
    return
  
  let pattern = args[1]
  let indexPath = args[2]
  var caseSensitive = true
  var maxResults = 100
  
  # Parse optional arguments
  for i in 3..<args.len:
    if args[i] == "--case-insensitive":
      caseSensitive = false
    elif args[i].startsWith("--max-results="):
      try:
        maxResults = parseInt(args[i].split("=")[1])
      except:
        echo "Warning: Invalid max-results value, using default: 100"
  
  if not fileExists(indexPath):
    echo &"Error: Index file not found: {indexPath}"
    return
  
  try:
    echo &"Searching for pattern: '{pattern}' in {indexPath}"
    echo &"Case sensitive: {caseSensitive}, Max results: {maxResults}"
    echo "---"
    
    let index = readIndexFromFile(indexPath)
    let results = ripgrepSearch(index, pattern, caseSensitive, maxResults)
    
    if results.len == 0:
      echo "No matches found."
      return
    
    echo &"Found {results.len} results:"
    echo ""
    
    for i, result in results:
      echo &"[{i+1}] {result.file.filename}:{result.lineNumber}"
      echo &"    {result.lineContent}"
      echo &"    Match at columns {result.matchStart}-{result.matchEnd}"
      echo ""
      
  except Exception as e:
    echo &"Error performing search: {e.msg}"

proc performEmbeddingSearch*(args: seq[string]) =
  ## Perform an embedding search from command line arguments.
  if args.len < 3:
    echo "Error: --embedding-search requires query and index-path"
    echo "Usage: fraggy --embedding-search <query> <index-path> [--max-results=N] [--model=MODEL]"
    return
  
  let query = args[1]
  let indexPath = args[2]
  var maxResults = 10
  var model = SimilarityEmbeddingModel
  
  # Parse optional arguments
  for i in 3..<args.len:
    if args[i].startsWith("--max-results="):
      try:
        maxResults = parseInt(args[i].split("=")[1])
      except:
        echo "Warning: Invalid max-results value, using default: 10"
    elif args[i].startsWith("--model="):
      model = args[i].split("=")[1]
  
  if not fileExists(indexPath):
    echo &"Error: Index file not found: {indexPath}"
    return
  
  try:
    echo &"Searching for: '{query}' in {indexPath}"
    echo &"Model: {model}, Max results: {maxResults}"
    echo "---"
    
    let index = readIndexFromFile(indexPath)
    let results = findSimilarFragments(index, query, maxResults, model)
    
    if results.len == 0:
      echo "No similar fragments found."
      return
    
    echo &"Found {results.len} similar fragments:"
    echo ""
    
    for i, result in results:
      echo &"[{i+1}] {result.file.filename} (similarity: {result.similarity:.3f})"
      echo &"    Lines {result.fragment.startLine}-{result.fragment.endLine}"
      echo &"    Type: {result.fragment.fragmentType}"
      echo &"    Score: {result.fragment.contentScore}"
      echo ""
      
  except Exception as e:
    echo &"Error performing search: {e.msg}"

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
  of "--ripgrep-search":
    performRipgrepSearch(args)
  of "--embedding-search":
    performEmbeddingSearch(args)
  else:
    echo &"Unknown command: {cmd}"
    echo ""
    printHelp()

when isMainModule:
  main()