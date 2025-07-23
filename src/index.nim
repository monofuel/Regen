## Indexing functionality for Fraggy - creating and managing file indexes

import
  std/[strutils, threadpool, strformat, os, times, osproc, algorithm],
  flatty, crunchy,
  ./types, ./search

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