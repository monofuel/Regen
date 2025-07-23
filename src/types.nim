## Shared types for Fraggy indexing and search functionality

type
  FraggyIndexType* = enum
    fraggy_git_repo
    fraggy_folder

  FraggyConfig* = object
    ## Configuration for fraggy indexing
    version*: string
    folders*: seq[string]  ## List of folder paths to index
    gitRepos*: seq[string] ## List of git repository paths to index
    extensions*: seq[string] ## File extensions to include in indexing
    embeddingModel*: string ## Model to use for embeddings

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

  SimilarityResult* = object
    ## A result from similarity search
    fragment*: FraggyFragment
    file*: FraggyFile
    similarity*: float32

  RipgrepResult* = object
    ## A result from ripgrep search
    file*: FraggyFile
    lineNumber*: int
    lineContent*: string
    matchStart*: int
    matchEnd*: int 