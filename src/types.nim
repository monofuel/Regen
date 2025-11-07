## Shared types for Regen indexing and search functionality
import std/tables

const
  #DefaultEmbeddingModel* = "Qwen/Qwen3-Embedding-0.6B-GGUF"
  #DefaultApiBaseUrl* = "http://10.11.2.16:1234/v1"
  DefaultEmbeddingModel* = "nomic-embed-text"
  DefaultApiBaseUrl* = "http://localhost:11434/v1"

type
  RegenIndexType* = enum
    regen_git_repo
    regen_folder

  RegenConfig* = object
    ## Configuration for regen indexing
    version*: string
    folders*: seq[string]  ## List of folder paths to index
    gitRepos*: seq[string] ## List of git repository paths to index
    extensions*: seq[string] ## File extensions to include in indexing (legacy)
    whitelistExtensions*: seq[string] ## Preferred allow-list of file extensions
    blacklistExtensions*: seq[string] ## Block-list of file extensions
    blacklistFilenames*: seq[string] ## Block-list of specific filenames (e.g., .env)
    embeddingModel*: string ## Model to use for embeddings
    apiBaseUrl*: string ## Base URL for the embeddings API (OpenAI-compatible)
    apiKey*: string ## Bearer token for API authentication

  RegenFragment* = object
    ## A specific chunk of the file
    startLine*: int
    endLine*: int
    embedding*: seq[float32]
    fragmentType*: string
    model*: string
    chunkAlgorithm*: string
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
    path*: string
    name*: string
    latestCommitHash*: string
    isDirty*: bool # does data match the latest commit?
    files*: Table[string, RegenFile]

  RegenFolder* = object
    ## indexing a specific folder on the local disk
    path*: string
    files*: Table[string, RegenFile]

  RegenIndex* = object
    ## a top level wrapper for a regen index.
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

  IndexVersionError* = ref object of CatchableError
    ## Exception raised when index file has incompatible version
    filepath*: string
    fileVersion*: int32
    expectedVersion*: int32 
