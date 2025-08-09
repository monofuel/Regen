## Indexing functionality for Regen - creating and managing file indexes

import
  std/[strutils, strformat, os, times, osproc, algorithm, sequtils],
  flatty, crunchy,
  ./types, ./search, ./configs, ./logs, ./fragment

const RegenFileIndexVersion* = 6

proc getIndexFormatPath(): string =
  ## Path to the standalone index format version file.
  let regenDir = getHomeDir() / ".regen"
  if not dirExists(regenDir):
    createDir(regenDir)
  result = regenDir / "INDEX_FORMAT"

proc purgeAllIndexFiles() =
  ## Delete all persisted index flat files.
  let regenDir = getHomeDir() / ".regen"
  let foldersDir = regenDir / "folders"
  if dirExists(foldersDir):
    for file in walkDir(foldersDir):
      if file.kind == pcFile and file.path.endsWith(".flat"):
        try: removeFile(file.path) except: discard
  let reposDir = regenDir / "repos"
  if dirExists(reposDir):
    for file in walkDir(reposDir):
      if file.kind == pcFile and file.path.endsWith(".flat"):
        try: removeFile(file.path) except: discard

proc ensureIndexFormatUpToDate*(): bool =
  ## Ensure on-disk index files match current format version.
  ## Returns true if format already matched; false if a purge was performed.
  let fmtPath = getIndexFormatPath()
  if fileExists(fmtPath):
    var existing = -1
    try:
      existing = parseInt(readFile(fmtPath).strip())
    except:
      existing = -1
    if existing != RegenFileIndexVersion:
      warn "Index format changed. Purging existing index files and requiring reindex..."
      purgeAllIndexFiles()
      writeFile(fmtPath, $RegenFileIndexVersion)
      return false
    return true
  else:
    # First run: establish the current format version file
    writeFile(fmtPath, $RegenFileIndexVersion)
    return true

proc writeIndexToFile*(index: RegenIndex, filepath: string) =
  ## Write a RegenIndex object to a file using flatty serialization.
  let data = toFlatty(index)
  writeFile(filepath, data)

proc readIndexFromFile*(filepath: string): RegenIndex =
  ## Read a RegenIndex object from a file using flatty deserialization.
  discard ensureIndexFormatUpToDate()
  let data = readFile(filepath)
  fromFlatty(data, RegenIndex)

# Legacy functions for backward compatibility
proc writeRepoToFile*(repo: RegenGitRepo, filepath: string) =
  ## Write a RegenGitRepo object to a file using flatty serialization.
  let index = RegenIndex(version: "0.1.0", kind: regen_git_repo, repo: repo)
  writeIndexToFile(index, filepath)

proc readRepoFromFile*(filepath: string): RegenGitRepo =
  ## Read a RegenGitRepo object from a file using flatty deserialization.
  let index = readIndexFromFile(filepath)
  if index.kind == regen_git_repo:
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

proc newRegenFragment*(content: string, filePath: string, startLine: int = 1, endLine: int = -1, chunkAlgorithm: string = "simple", fragmentType: string = "document"): RegenFragment =
  ## Create a new RegenFragment from content and metadata.
  let actualEndLine = if endLine == -1: content.split('\n').len else: endLine
  let cfg = loadConfig()
  let embedding = generateEmbedding(content, cfg.embeddingModel)

  result = RegenFragment(
    startLine: startLine,
    endLine: actualEndLine,
    embedding: embedding,
    fragmentType: fragmentType,
    model: cfg.embeddingModel,
    chunkAlgorithm: chunkAlgorithm,
    private: false,
    contentScore: (if content.len > 1000: 90 else: 70),
    hash: createFileHash(content)
  )

proc newRegenFile*(filePath: string): RegenFile =
  ## Create a new RegenFile by reading and processing the file into multiple fragments.
  let content = readFile(filePath)
  let fileInfo = getFileInfo(filePath)

  # Determine fragment ranges using the fragmenting system
  let chunks = chunkFile(filePath, content)

  # Helper to extract content for a given line range (1-based inclusive)
  let allLines = content.split('\n')
  proc sliceContent(startLine, endLine: int): string =
    var pieces: seq[string] = @[]
    let startIdx = max(0, startLine - 1)
    let endIdx = min(allLines.len - 1, endLine - 1)
    for i in startIdx..endIdx:
      pieces.add(allLines[i])
    result = pieces.join("\n")

  var fragments: seq[RegenFragment] = @[]
  let fragmentType = "document"
  for ch in chunks:
    let fragText = sliceContent(ch.startLine, ch.endLine)
    if fragText.len == 0:
      continue
    let frag = newRegenFragment(
      content = fragText,
      filePath = filePath,
      startLine = ch.startLine,
      endLine = ch.endLine,
      chunkAlgorithm = ch.chunkAlgorithm,
      fragmentType = fragmentType
    )
    fragments.add(frag)

  # Fallback: if no fragments were produced (e.g., empty file), create a single empty fragment
  if fragments.len == 0:
    let frag = newRegenFragment("", filePath, 1, 1, chunkAlgorithm = "simple", fragmentType = fragmentType)
    fragments.add(frag)

  result = RegenFile(
    path: filePath,
    filename: extractFilename(filePath),
    hash: createFileHash(content),
    creationTime: fileInfo.creationTime.toUnix().float,
    lastModified: fileInfo.lastWriteTime.toUnix().float,
    fragments: fragments
  )

proc filenameMatches(name: string, pattern: string): bool =
  ## Simple wildcard match supporting a single '*' character.
  let starIndex = pattern.find('*')
  if starIndex == -1:
    return name == pattern
  let prefix = if starIndex > 0: pattern[0 ..< starIndex] else: ""
  let suffix = if starIndex + 1 <= pattern.high: pattern[starIndex + 1 .. pattern.high] else: ""
  if prefix.len > 0 and not name.startsWith(prefix):
    return false
  if suffix.len > 0 and not name.endsWith(suffix):
    return false
  if prefix.len + suffix.len > name.len:
    return false
  true

proc shouldInclude*(path: string, whitelist: seq[string], blacklistExtensions: seq[string], blacklistFilenames: seq[string]): bool =
  ## Decide whether a file should be included based on extension and filename filters.
  let (_, name, ext) = splitFile(path)
  let lowerExt = ext.toLower
  # Extension-based block
  if lowerExt in blacklistExtensions:
    return false
  # Filename-based block (supports simple '*' wildcard)
  let base = extractFilename(path)
  for patt in blacklistFilenames:
    if filenameMatches(base, patt):
      return false
  # Whitelist extension enforcement
  if whitelist.len > 0 and lowerExt notin whitelist:
    return false
  true

proc findProjectFiles*(rootPath: string, whitelist: seq[string], blacklistExtensions: seq[string], blacklistFilenames: seq[string]): seq[string] =
  ## Find all files that pass whitelist/blacklist filters in the project directory.
  result = @[]
  
  for path in walkDirRec(rootPath, yieldFilter = {pcFile}):
    if shouldInclude(path, whitelist, blacklistExtensions, blacklistFilenames):
      result.add(path)
  
  # Sort for consistent ordering
  result.sort()

proc findProjectFiles*(rootPath: string, whitelist: seq[string]): seq[string] =
  ## Backward-compatible overload using config-defined blacklists.
  let cfg = loadConfig()
  findProjectFiles(rootPath, whitelist, cfg.blacklistExtensions, cfg.blacklistFilenames)

proc newRegenGitRepo*(repoPath: string, whitelist: seq[string], blacklistExtensions: seq[string], blacklistFilenames: seq[string]): RegenGitRepo =
  ## Create a new RegenGitRepo by scanning the repository (serial to control memory).
  let filePaths = findProjectFiles(repoPath, whitelist, blacklistExtensions, blacklistFilenames)
  
  var regenFiles: seq[RegenFile] = @[]
  for filePath in filePaths:
    regenFiles.add(newRegenFile(filePath))
  
  result = RegenGitRepo(
    name: extractFilename(repoPath),
    latestCommitHash: getGitCommitHash(repoPath),
    isDirty: isGitDirty(repoPath),
    files: regenFiles
  )

proc newRegenFolder*(folderPath: string, whitelist: seq[string] = @[], blacklistExtensions: seq[string] = @[], blacklistFilenames: seq[string] = @[]): RegenFolder =
  ## Create a new RegenFolder by scanning the folder (serial to control memory).
  let filePaths = findProjectFiles(folderPath, whitelist, blacklistExtensions, blacklistFilenames)
  
  var regenFiles: seq[RegenFile] = @[]
  for filePath in filePaths:
    regenFiles.add(newRegenFile(filePath))
  
  result = RegenFolder(
    path: folderPath,
    files: regenFiles
  )

proc newRegenIndex*(indexType: RegenIndexType, path: string, whitelist: seq[string], blacklistExtensions: seq[string], blacklistFilenames: seq[string]): RegenIndex =
  ## Create a new RegenIndex of the specified type using parallel processing.
  result = RegenIndex(version: "0.1.0", kind: indexType)
  
  case indexType
  of regen_git_repo:
    result.repo = newRegenGitRepo(path, whitelist, blacklistExtensions, blacklistFilenames)
  of regen_folder:
    result.folder = newRegenFolder(path, whitelist, blacklistExtensions, blacklistFilenames) 

proc newRegenIndex*(indexType: RegenIndexType, path: string, whitelist: seq[string]): RegenIndex =
  ## Backward-compatible overload using config-defined blacklists.
  let cfg = loadConfig()
  newRegenIndex(indexType, path, whitelist, cfg.blacklistExtensions, cfg.blacklistFilenames)

proc newRegenIndex*(indexType: RegenIndexType, path: string, whitelist: seq[string], blacklistExtensions: seq[string]): RegenIndex =
  ## Backward-compatible overload taking only extension blacklist.
  let cfg = loadConfig()
  newRegenIndex(indexType, path, whitelist, blacklistExtensions, cfg.blacklistFilenames)

proc needsReindexing*(existingFile: RegenFile, currentPath: string): bool =
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

proc updateRegenIndex*(existingIndex: RegenIndex, currentPath: string, whitelist: seq[string], blacklistExtensions: seq[string], blacklistFilenames: seq[string]): tuple[index: RegenIndex, changed: bool] =
  ## Update an existing index with only the files that have changed.
  var updated = existingIndex
  
  info "Checking for changes..."
  let currentFiles = findProjectFiles(currentPath, whitelist, blacklistExtensions, blacklistFilenames)
  var filesToUpdate: seq[string] = @[]
  var filesToRemove: seq[int] = @[]
  
  case updated.kind:
  of regen_folder:
    # Check existing files for changes
    for i, existingFile in updated.folder.files:
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
      let existsInIndex = updated.folder.files.anyIt(it.path == currentFile)
      if not existsInIndex:
        filesToUpdate.add(currentFile)
        info &"    - New: {extractFilename(currentFile)}"
    
    # Remove deleted files (in reverse order to maintain indices)
    for i in countdown(filesToRemove.len - 1, 0):
      updated.folder.files.delete(filesToRemove[i])
    
    # Update/add changed files
    if filesToUpdate.len > 0:
      info &"Reindexing {filesToUpdate.len} files..."
      
      # Process serially to limit memory usage
      for filePath in filesToUpdate:
        let newFile = newRegenFile(filePath)
        var existingIdx = -1
        for i, file in updated.folder.files:
          if file.path == newFile.path:
            existingIdx = i
            break
        if existingIdx >= 0:
          updated.folder.files[existingIdx] = newFile
        else:
          updated.folder.files.add(newFile)
  
  of regen_git_repo:
    # Update git-specific info
    updated.repo.latestCommitHash = getGitCommitHash(currentPath)
    updated.repo.isDirty = isGitDirty(currentPath)
    
    # Check existing files for changes
    for i, existingFile in updated.repo.files:
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
      let existsInIndex = updated.repo.files.anyIt(it.path == currentFile)
      if not existsInIndex:
        filesToUpdate.add(currentFile)
        info &"    - New: {extractFilename(currentFile)}"
    
    # Remove deleted files (in reverse order to maintain indices)
    for i in countdown(filesToRemove.len - 1, 0):
      updated.repo.files.delete(filesToRemove[i])
    
    # Update/add changed files
    if filesToUpdate.len > 0:
      info &"Reindexing {filesToUpdate.len} files..."
      
      # Process serially to limit memory usage
      for filePath in filesToUpdate:
        let newFile = newRegenFile(filePath)
        var existingIdx = -1
        for i, file in updated.repo.files:
          if file.path == newFile.path:
            existingIdx = i
            break
        if existingIdx >= 0:
          updated.repo.files[existingIdx] = newFile
        else:
          updated.repo.files.add(newFile)
  
  let hasChanges = not (filesToUpdate.len == 0 and filesToRemove.len == 0)
  if not hasChanges:
    info "No changes detected"
  result = (updated, hasChanges)

proc indexAll*() =
  ## Index all configured folders and git repositories with intelligent incremental updates.
  let _ = ensureIndexFormatUpToDate()
  let config = loadConfig()
  
  let whitelist = if config.whitelistExtensions.len > 0: config.whitelistExtensions else: config.extensions
  let blacklistExts = config.blacklistExtensions
  let blacklistNames = config.blacklistFilenames

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
    let indexPath = getHomeDir() / ".regen" / "folders" / &"{safefolderName}.flat"
    createDir(parentDir(indexPath))
    
    var index: RegenIndex
    var changed = false
    
    if fileExists(indexPath):
      # Load existing index and update incrementally
      try:
        let existingIndex = readIndexFromFile(indexPath)
        if existingIndex.kind == regen_folder:
          let (updatedIndex, didChange) = updateRegenIndex(existingIndex, folderPath, whitelist, blacklistExts, blacklistNames)
          changed = didChange
          if not changed:
            info "Unchanged; skipping write"
            index = existingIndex
          else:
            index = updatedIndex
        else:
          warn "Existing index is wrong type, rebuilding..."
          let folder = newRegenFolder(folderPath, whitelist, blacklistExts, blacklistNames)
          index = RegenIndex(version: ConfigVersion, kind: regen_folder, folder: folder)
          changed = true
      except:
        warn "Could not load existing index, rebuilding..."
        let folder = newRegenFolder(folderPath, whitelist, blacklistExts, blacklistNames)
        index = RegenIndex(version: ConfigVersion, kind: regen_folder, folder: folder)
        changed = true
    else:
      # Create new index
      info "Creating new index..."
      let folder = newRegenFolder(folderPath, whitelist, blacklistExts, blacklistNames)
      index = RegenIndex(version: ConfigVersion, kind: regen_folder, folder: folder)
      changed = true
    
    # Only persist if we actually rebuilt or updated
    if changed:
      writeIndexToFile(index, indexPath)
      info &"Saved index to: {indexPath}"
    else:
      info "No index write necessary"
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
    let indexPath = getHomeDir() / ".regen" / "repos" / &"{repoName}.flat"
    createDir(parentDir(indexPath))
    
    var index: RegenIndex
    var changed = false
    
    if fileExists(indexPath):
      # Load existing index and update incrementally
      try:
        let existingIndex = readIndexFromFile(indexPath)
        if existingIndex.kind == regen_git_repo:
          let (updatedIndex, didChange) = updateRegenIndex(existingIndex, repoPath, whitelist, blacklistExts, blacklistNames)
          changed = didChange
          if not changed:
            info "Unchanged; skipping write"
            index = existingIndex
          else:
            index = updatedIndex
        else:
          warn "Existing index is wrong type, rebuilding..."
          let repo = newRegenGitRepo(repoPath, whitelist, blacklistExts, blacklistNames)
          index = RegenIndex(version: ConfigVersion, kind: regen_git_repo, repo: repo)
          changed = true
      except:
        warn "Could not load existing index, rebuilding..."
        let repo = newRegenGitRepo(repoPath, whitelist, blacklistExts, blacklistNames)
        index = RegenIndex(version: ConfigVersion, kind: regen_git_repo, repo: repo)
        changed = true
    else:
      # Create new index
      info "Creating new index..."
      let repo = newRegenGitRepo(repoPath, whitelist, blacklistExts, blacklistNames)
      index = RegenIndex(version: ConfigVersion, kind: regen_git_repo, repo: repo)
      changed = true
    
    # Only persist if we actually rebuilt or updated
    if changed:
      writeIndexToFile(index, indexPath)
      info &"Saved index to: {indexPath}"
    else:
      info "No index write necessary"
    info &"Indexed {index.repo.files.len} files"
    let commitHash = getGitCommitHash(repoPath)
    let isDirty = isGitDirty(repoPath)
    let shortCommit = if commitHash.len >= 8: commitHash[0..7] else: commitHash
    let ellipsis = if commitHash.len >= 8: "..." else: ""
    info &"Commit: {shortCommit}{ellipsis} (dirty: {isDirty})"
