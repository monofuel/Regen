import
  std/[strutils, threadpool, strformat, os, times, osproc, algorithm, math],
  flatty, openai_leap, crunchy

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

const
  SimilarityEmbeddingModel* = "nomic-embed-text"
  MaxInFlight* = 10

# Solution-nine server
# radeon pro w7500
var localOllamaApi* = newOpenAiApi(
  baseUrl = "http://10.11.2.16:11434/v1", 
  apiKey = "ollama",
  maxInFlight = MaxInFlight
)

type
  FraggyIndexType* = enum
    fraggy_git_repo
    fraggy_folder

  FraggyFragment* = object
    ## A specific chunk of the file
    startLine*: int
    endLine*: int
    embedding*: seq[float32]
    fragmentType*: string
    model*: string
    private*: bool
    contentScore*: int
    hash*: string

  FraggyFile* = object
    ## A specific file that has been indexed.
    path*: string
    filename*: string
    hash*: string
    creationTime*: float
    lastModified*: float
    fragments*: seq[FraggyFragment]

  FraggyGitRepo* = object
    ## indexing a git repo for a specific commit
    name*: string
    latestCommitHash*: string
    isDirty*: bool # does data match the latest commit?
    files*: seq[FraggyFile]

  FraggyFolder* = object
    ## indexing a specific folder on the local disk
    path*: string
    files*: seq[FraggyFile]

  FraggyIndex* = object
    ## a top level wrapper for a fraggy index.
    version*: string
    case kind*: FraggyIndexType
    of fraggy_git_repo:
      repo*: FraggyGitRepo
    of fraggy_folder:
      folder*: FraggyFolder

proc generateEmbedding*(text: string, model: string = SimilarityEmbeddingModel): seq[float32] =
  ## Generate an embedding for the given text using ollama.
  let embedding = localOllamaApi.generateEmbeddings(
    model = model,
    input = text
  )
  result = embedding.data[0].embedding

proc generateEmbeddingsBatch*(texts: seq[string], model: string = SimilarityEmbeddingModel): seq[seq[float32]] =
  ## Generate embeddings for multiple texts in parallel.
  var futures: seq[FlowVar[seq[float32]]] = @[]
  
  # Spawn all embedding requests in parallel
  for text in texts:
    futures.add(spawn generateEmbedding(text, model))
  
  # Collect results
  result = @[]
  for future in futures:
    result.add(^future)

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

type
  SimilarityResult* = object
    ## A result from similarity search
    fragment*: FraggyFragment
    file*: FraggyFile
    similarity*: float32

proc cosineSimilarity*(a, b: seq[float32]): float32 =
  ## Calculate cosine similarity between two embedding vectors.
  if a.len != b.len:
    raise newException(ValueError, "Vectors must have the same length")
  
  var dotProduct = 0.0'f32
  var normA = 0.0'f32
  var normB = 0.0'f32
  
  for i in 0..<a.len:
    dotProduct += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  
  let magnitude = sqrt(normA) * sqrt(normB)
  if magnitude == 0.0'f32:
    return 0.0'f32
  
  result = dotProduct / magnitude

proc findSimilarFragments*(index: FraggyIndex, queryText: string, maxResults: int = 10, model: string = SimilarityEmbeddingModel): seq[SimilarityResult] =
  ## Find the most similar fragments to the query text.
  let queryEmbedding = generateEmbedding(queryText, model)
  var results: seq[SimilarityResult] = @[]
  
  # Collect all fragments with their similarity scores
  case index.kind
  of fraggy_git_repo:
    for file in index.repo.files:
      for fragment in file.fragments:
        if fragment.model == model:
          let similarity = cosineSimilarity(queryEmbedding, fragment.embedding)
          results.add(SimilarityResult(
            fragment: fragment,
            file: file,
            similarity: similarity
          ))
  of fraggy_folder:
    for file in index.folder.files:
      for fragment in file.fragments:
        if fragment.model == model:
          let similarity = cosineSimilarity(queryEmbedding, fragment.embedding)
          results.add(SimilarityResult(
            fragment: fragment,
            file: file,
            similarity: similarity
          ))
  
  # Sort by similarity (highest first) and return top results
  results.sort(proc(a, b: SimilarityResult): int =
    if a.similarity > b.similarity: -1
    elif a.similarity < b.similarity: 1
    else: 0
  )
  
  if results.len > maxResults:
    result = results[0..<maxResults]
  else:
    result = results

proc main() =
  echo "Hello, World!"

when isMainModule:
  main()