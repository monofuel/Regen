## Shared types for Regen indexing and search functionality

type
  RegenIndexType* = enum
    regen_git_repo
    regen_folder

  RegenConfig* = object
    ## Configuration for regen indexing
    version*: string
    folders*: seq[string]  ## List of folder paths to index
    gitRepos*: seq[string] ## List of git repository paths to index
    extensions*: seq[string] ## File extensions to include in indexing
    embeddingModel*: string ## Model to use for embeddings
    apiKey*: string ## Bearer token for API authentication

  RegenFragment* = object
    ## A specific chunk of the file
    startLine*: int
    endLine*: int
    embedding*: seq[float32]
    fragmentType*: string
    model*: string
    private*: bool
    contentScore*: int
    hash*: string

  RegenFile* = object
    ## A specific file that has been indexed.
    path*: string
    filename*: string
    hash*: string
    creationTime*: float
    lastModified*: float
    fragments*: seq[RegenFragment]

  RegenGitRepo* = object
    ## indexing a git repo for a specific commit
    name*: string
    latestCommitHash*: string
    isDirty*: bool # does data match the latest commit?
    files*: seq[RegenFile]

  RegenFolder* = object
    ## indexing a specific folder on the local disk
    path*: string
    files*: seq[RegenFile]

  RegenIndex* = object
    ## a top level wrapper for a regen index.
    version*: string
    case kind*: RegenIndexType
    of regen_git_repo:
      repo*: RegenGitRepo
    of regen_folder:
      folder*: RegenFolder

  SimilarityResult* = object
    ## A result from similarity search
    fragment*: RegenFragment
    file*: RegenFile
    similarity*: float32

  RipgrepResult* = object
    ## A result from ripgrep search
    file*: RegenFile
    lineNumber*: int
    lineContent*: string
    matchStart*: int
    matchEnd*: int 
