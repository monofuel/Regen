import
  flatty

# flatty is used to serialize/deserialize to flat files
# top level organization is a git repo, eg monofuel/fragg or monolab/racha
# each repo has many files
# each file has many fragments
# each fragment has a line start, end, and an embedding vector

# nomic-embed-text is used for similarity search with local embeddings and ollama.

# the index flatfiles will be saved at ~/.fraggy/{git_owner}/{git_repo}/{embedding_model_name}.flat
# multiple embedding models may be used for a single repo, and kept in separate files.

type
  FraggyFragment* = object
    startLine*: int
    endLine*: int
    embedding*: seq[float]
    fragmentType*: string
    model*: string
    private*: bool
    contentScore*: int
    hash*: string

  FraggyFile* = object
    hostname*: string
    path*: string
    filename*: string
    hash*: string
    creationTime*: float
    lastModified*: float
    fragments*: seq[FraggyFragment]

  FraggyGitRepo* = object
    name*: string
    latestCommitHash*: string
    files*: seq[FraggyFile]

proc writeRepoToFile*(repo: FraggyGitRepo, filepath: string) =
  ## Write a FraggyGitRepo object to a file using flatty serialization.
  let data = toFlatty(repo)
  writeFile(filepath, data)

proc readRepoFromFile*(filepath: string): FraggyGitRepo =
  ## Read a FraggyGitRepo object from a file using flatty deserialization.
  let data = readFile(filepath)
  fromFlatty(data, FraggyGitRepo)