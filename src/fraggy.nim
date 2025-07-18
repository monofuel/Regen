import
  flatty, openai_leap

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

# Solution-nine server
# radeon pro w7500
var localOllamaApi* = newOpenAiApi(
  baseUrl = "http://localhost:11434/v1", 
  apiKey = "ollama",
)

type
  FraggyIndexType* = enum
    fraggy_git_repo
    fraggy_folder

  FraggyFragment* = object
    ## A specific chunk of the file
    startLine*: int
    endLine*: int
    embedding*: seq[float]
    fragmentType*: string
    model*: string
    private*: bool
    contentScore*: int
    hash*: string

  FraggyFile* = object
    ## A specific file that has been indexed.
    hostname*: string
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

proc generateEmbedding*(text: string, model: string = SimilarityEmbeddingModel): seq[float] =
  ## Generate an embedding for the given text using ollama.
  let embedding = localOllamaApi.generateEmbeddings(
    model = model,
    input = text
  )
  result = embedding.data[0].embedding

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

proc main() =
  echo "Hello, World!"

when isMainModule:
  main()