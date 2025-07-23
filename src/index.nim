## Indexing functionality for Fraggy - creating and managing file indexes

import
  std/[strutils, threadpool, strformat, os, times, osproc, algorithm, sequtils],
  flatty, crunchy,
  ./types, ./search, ./configs, ./logs

proc writeIndexToFile*(index: FraggyIndex, filepath: string) =
  ## Write a FraggyIndex object to a file using flatty serialization.
  let data = toFlatty(index)
  writeFile(filepath, data)

proc readIndexFromFile*(filepath: string): FraggyIndex =
  ## Read a FraggyIndex object from a file using flatty deserialization.
  let data = readFile(filepath)
  fromFlatty(data, FraggyIndex)

# Legacy functions for backward compatibility
proc writeRepoToFile*(repo: FraggyGitRepo, filepath: string) =
  ## Write a FraggyGitRepo object to a file using flatty serialization.
  let index = FraggyIndex(version: "0.1.0", kind: fraggy_git_repo, repo: repo)
  writeIndexToFile(index, filepath)

proc readRepoFromFile*(filepath: string): FraggyGitRepo =
  ## Read a FraggyGitRepo object from a file using flatty deserialization.
  let index = readIndexFromFile(filepath)
  if index.kind == fraggy_git_repo:
    result = index.repo
  else:
    raise newException(ValueError, "File does not contain a git repo index")

proc createFileHash*(content: string): string =
  ## Create a SHA-256 hash of file content for tracking changes.
  result = sha256(content).toHex()

proc getGitCommitHash*(repoPath: string): string =
  ## Get the current git commit hash.
  try:
    let (output, exitCode) = execCmdEx(&"cd {repoPath} && git rev-parse HEAD")
    if exitCode == 0:
      result = output.strip()
    else:
      result = "unknown"
  except:
    result = "unknown"

proc isGitDirty*(repoPath: string): bool =
  ## Check if the git repository has uncommitted changes.
  try:
    let (output, exitCode) = execCmdEx(&"cd {repoPath} && git status --porcelain")
    result = exitCode != 0 or output.strip().len > 0
  except:
    result = true

proc newFraggyFragment*(content: string, filePath: string, startLine: int = 1, endLine: int = -1): FraggyFragment =
  ## Create a new FraggyFragment from content.
  let actualEndLine = if endLine == -1: content.split('\n').len else: endLine
  let embedding = generateEmbedding(content)
  
  result = FraggyFragment(
    startLine: startLine,
    endLine: actualEndLine,
    embedding: embedding,
    fragmentType: "file",
    model: SimilarityEmbeddingModel,
    private: false,
    contentScore: if content.len > 1000: 90 else: 70,
    hash: createFileHash(content)
  )

proc newFraggyFile*(filePath: string): FraggyFile =
  ## Create a new FraggyFile by reading and processing the file.
  let content = readFile(filePath)
  let fileInfo = getFileInfo(filePath)
  let fragment = newFraggyFragment(content, filePath)
  
  result = FraggyFile(
    path: filePath,
    filename: extractFilename(filePath),
    hash: createFileHash(content),
    creationTime: fileInfo.creationTime.toUnix().float,
    lastModified: fileInfo.lastWriteTime.toUnix().float,
    fragments: @[fragment]
  )

proc findProjectFiles*(rootPath: string, extensions: seq[string]): seq[string] =
  ## Find all files with specified extensions in the project directory.
  result = @[]
  
  for path in walkDirRec(rootPath, yieldFilter = {pcFile}):
    let ext = splitFile(path).ext
    if ext in extensions:
      result.add(path)
  
  # Sort for consistent ordering
  result.sort()

proc newFraggyGitRepo*(repoPath: string, extensions: seq[string]): FraggyGitRepo =
  ## Create a new FraggyGitRepo by scanning the repository in parallel.
  let filePaths = findProjectFiles(repoPath, extensions)
  
  # Process all files in parallel
  var fileFutures: seq[FlowVar[FraggyFile]] = @[]
  for filePath in filePaths:
    fileFutures.add(spawn newFraggyFile(filePath))
  
  var fraggyFiles: seq[FraggyFile] = @[]
  for future in fileFutures:
    fraggyFiles.add(^future)
  
  result = FraggyGitRepo(
    name: extractFilename(repoPath),
    latestCommitHash: getGitCommitHash(repoPath),
    isDirty: isGitDirty(repoPath),
    files: fraggyFiles
  )

proc newFraggyFolder*(folderPath: string, extensions: seq[string]): FraggyFolder =
  ## Create a new FraggyFolder by scanning the folder in parallel.
  let filePaths = findProjectFiles(folderPath, extensions)
  
  # Process all files in parallel
  var fileFutures: seq[FlowVar[FraggyFile]] = @[]
  for filePath in filePaths:
    fileFutures.add(spawn newFraggyFile(filePath))
  
  var fraggyFiles: seq[FraggyFile] = @[]
  for future in fileFutures:
    fraggyFiles.add(^future)
  
  result = FraggyFolder(
    path: folderPath,
    files: fraggyFiles
  )

proc newFraggyIndex*(indexType: FraggyIndexType, path: string, extensions: seq[string]): FraggyIndex =
  ## Create a new FraggyIndex of the specified type using parallel processing.
  result = FraggyIndex(version: "0.1.0", kind: indexType)
  
  case indexType
  of fraggy_git_repo:
    result.repo = newFraggyGitRepo(path, extensions)
  of fraggy_folder:
    result.folder = newFraggyFolder(path, extensions) 

proc needsReindexing*(existingFile: FraggyFile, currentPath: string): bool =
  ## Check if a file needs to be reindexed based on modification time and hash.
  if not fileExists(currentPath):
    return true
  
  let currentInfo = getFileInfo(currentPath)
  let currentModTime = currentInfo.lastWriteTime.toUnix().float
  
  # Check if file has been modified since last index
  if currentModTime > existingFile.lastModified:
    return true
  
  # Double-check with hash comparison for safety
  try:
    let currentContent = readFile(currentPath)
    let currentHash = createFileHash(currentContent)
    return currentHash != existingFile.hash
  except:
    return true

proc updateFraggyIndex*(existingIndex: FraggyIndex, currentPath: string, extensions: seq[string]): FraggyIndex =
  ## Update an existing index with only the files that have changed.
  result = existingIndex
  
  info "Checking for changes..."
  let currentFiles = findProjectFiles(currentPath, extensions)
  var filesToUpdate: seq[string] = @[]
  var filesToRemove: seq[int] = @[]
  
  case result.kind:
  of fraggy_folder:
    # Check existing files for changes
    for i, existingFile in result.folder.files:
      if existingFile.path notin currentFiles:
        # File was deleted
        filesToRemove.add(i)
        info &"    - Removed: {existingFile.filename}"
      elif needsReindexing(existingFile, existingFile.path):
        # File was modified
        filesToUpdate.add(existingFile.path)
        info &"    - Modified: {existingFile.filename}"
    
    # Check for new files
    for currentFile in currentFiles:
      let existsInIndex = result.folder.files.anyIt(it.path == currentFile)
      if not existsInIndex:
        filesToUpdate.add(currentFile)
        info &"    - New: {extractFilename(currentFile)}"
    
    # Remove deleted files (in reverse order to maintain indices)
    for i in countdown(filesToRemove.len - 1, 0):
      result.folder.files.delete(filesToRemove[i])
    
    # Update/add changed files
    if filesToUpdate.len > 0:
      info &"Reindexing {filesToUpdate.len} files..."
      
      # Process files in parallel if there are many
      if filesToUpdate.len > 3:
        var fileFutures: seq[FlowVar[FraggyFile]] = @[]
        for filePath in filesToUpdate:
          fileFutures.add(spawn newFraggyFile(filePath))
        
        for future in fileFutures:
          let newFile = ^future
          # Replace existing or add new
          var existingIdx = -1
          for i, file in result.folder.files:
            if file.path == newFile.path:
              existingIdx = i
              break
          if existingIdx >= 0:
            result.folder.files[existingIdx] = newFile
          else:
            result.folder.files.add(newFile)
      else:
        # Process serially for small numbers
        for filePath in filesToUpdate:
          let newFile = newFraggyFile(filePath)
          var existingIdx = -1
          for i, file in result.folder.files:
            if file.path == newFile.path:
              existingIdx = i
              break
          if existingIdx >= 0:
            result.folder.files[existingIdx] = newFile
          else:
            result.folder.files.add(newFile)
  
  of fraggy_git_repo:
    # Update git-specific info
    result.repo.latestCommitHash = getGitCommitHash(currentPath)
    result.repo.isDirty = isGitDirty(currentPath)
    
    # Check existing files for changes
    for i, existingFile in result.repo.files:
      if existingFile.path notin currentFiles:
        # File was deleted
        filesToRemove.add(i)
        info &"    - Removed: {existingFile.filename}"
      elif needsReindexing(existingFile, existingFile.path):
        # File was modified
        filesToUpdate.add(existingFile.path)
        info &"    - Modified: {existingFile.filename}"
    
    # Check for new files
    for currentFile in currentFiles:
      let existsInIndex = result.repo.files.anyIt(it.path == currentFile)
      if not existsInIndex:
        filesToUpdate.add(currentFile)
        info &"    - New: {extractFilename(currentFile)}"
    
    # Remove deleted files (in reverse order to maintain indices)
    for i in countdown(filesToRemove.len - 1, 0):
      result.repo.files.delete(filesToRemove[i])
    
    # Update/add changed files
    if filesToUpdate.len > 0:
      info &"Reindexing {filesToUpdate.len} files..."
      
      # Process files in parallel if there are many
      if filesToUpdate.len > 3:
        var fileFutures: seq[FlowVar[FraggyFile]] = @[]
        for filePath in filesToUpdate:
          fileFutures.add(spawn newFraggyFile(filePath))
        
        for future in fileFutures:
          let newFile = ^future
          # Replace existing or add new
          var existingIdx = -1
          for i, file in result.repo.files:
            if file.path == newFile.path:
              existingIdx = i
              break
          if existingIdx >= 0:
            result.repo.files[existingIdx] = newFile
          else:
            result.repo.files.add(newFile)
      else:
        # Process serially for small numbers
        for filePath in filesToUpdate:
          let newFile = newFraggyFile(filePath)
          var existingIdx = -1
          for i, file in result.repo.files:
            if file.path == newFile.path:
              existingIdx = i
              break
          if existingIdx >= 0:
            result.repo.files[existingIdx] = newFile
          else:
            result.repo.files.add(newFile)
  
  if filesToUpdate.len == 0 and filesToRemove.len == 0:
    info "No changes detected"

proc indexAll*() =
  ## Index all configured folders and git repositories with intelligent incremental updates.
  let config = loadConfig()
  
  info "Indexing all configured paths..."
  
  # Index folders
  for folderPath in config.folders:
    if not dirExists(folderPath):
      warn &"Folder does not exist: {folderPath}"
      continue
    
    info &"Indexing folder: {folderPath}"
    
    # Generate simpler filename without hash
    let folderName = extractFilename(folderPath)
    let safefolderName = folderName.replace("/", "_").replace("\\", "_")
    let indexPath = getHomeDir() / ".fraggy" / "folders" / &"{safefolderName}.flat"
    createDir(parentDir(indexPath))
    
    var index: FraggyIndex
    
    if fileExists(indexPath):
      # Load existing index and update incrementally
      try:
        let existingIndex = readIndexFromFile(indexPath)
        if existingIndex.kind == fraggy_folder:
          index = updateFraggyIndex(existingIndex, folderPath, config.extensions)
        else:
          warn "Existing index is wrong type, rebuilding..."
          let folder = newFraggyFolder(folderPath, config.extensions)
          index = FraggyIndex(version: ConfigVersion, kind: fraggy_folder, folder: folder)
      except:
        warn "Could not load existing index, rebuilding..."
        let folder = newFraggyFolder(folderPath, config.extensions)
        index = FraggyIndex(version: ConfigVersion, kind: fraggy_folder, folder: folder)
    else:
      # Create new index
      info "Creating new index..."
      let folder = newFraggyFolder(folderPath, config.extensions)
      index = FraggyIndex(version: ConfigVersion, kind: fraggy_folder, folder: folder)
    
    writeIndexToFile(index, indexPath)
    info &"Saved index to: {indexPath}"
    info &"Indexed {index.folder.files.len} files"
  
  # Index git repos
  for repoPath in config.gitRepos:
    if not dirExists(repoPath):
      warn &"Git repo does not exist: {repoPath}"
      continue
    
    if not dirExists(repoPath / ".git"):
      warn &"{repoPath} is not a git repository"
      continue
    
    info &"Indexing git repo: {repoPath}"
    
    # Generate filename using just repo name (no commit hash)
    let repoName = extractFilename(repoPath)
    let indexPath = getHomeDir() / ".fraggy" / "repos" / &"{repoName}.flat"
    createDir(parentDir(indexPath))
    
    var index: FraggyIndex
    
    if fileExists(indexPath):
      # Load existing index and update incrementally
      try:
        let existingIndex = readIndexFromFile(indexPath)
        if existingIndex.kind == fraggy_git_repo:
          index = updateFraggyIndex(existingIndex, repoPath, config.extensions)
        else:
          warn "Existing index is wrong type, rebuilding..."
          let repo = newFraggyGitRepo(repoPath, config.extensions)
          index = FraggyIndex(version: ConfigVersion, kind: fraggy_git_repo, repo: repo)
      except:
        warn "Could not load existing index, rebuilding..."
        let repo = newFraggyGitRepo(repoPath, config.extensions)
        index = FraggyIndex(version: ConfigVersion, kind: fraggy_git_repo, repo: repo)
    else:
      # Create new index
      info "Creating new index..."
      let repo = newFraggyGitRepo(repoPath, config.extensions)
      index = FraggyIndex(version: ConfigVersion, kind: fraggy_git_repo, repo: repo)
    
    writeIndexToFile(index, indexPath)
    info &"Saved index to: {indexPath}"
    info &"Indexed {index.repo.files.len} files"
    let commitHash = getGitCommitHash(repoPath)
    let isDirty = isGitDirty(repoPath)
    info &"Commit: {commitHash[0..7]}... (dirty: {isDirty})" 