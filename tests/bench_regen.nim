import
  std/[os, strformat, threadpool, tables],
  benchy,
  openai_leap,
  ../src/regen

const
  WhitelistedExtensions = [".nim", ".md"]



proc benchmarkFileReading() =
  ## Benchmark file discovery and reading.
  timeIt "File Discovery":
    let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
    keep files.len

  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  var totalContent = ""
  
  timeIt "File Reading":
    for filePath in files:
      let content = readFile(filePath)
      totalContent.add content
    keep totalContent.len

proc benchmarkHashing() =
  ## Benchmark content hashing.
  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  var contents: seq[string] = @[]
  
  # Pre-read files for fair comparison
  for filePath in files:
    contents.add readFile(filePath)
  
  timeIt "SHA-256 Hashing":
    for content in contents:
      let hash = createFileHash(content)
      keep hash

proc benchmarkEmbeddings() =
  ## Benchmark embedding generation (this will be slower due to Ollama).
  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  var contents: seq[string] = @[]
  
  # Pre-read files and take smaller samples for embedding tests
  for filePath in files:
    let content = readFile(filePath)
    # Take first 500 chars to make embedding tests faster
    let sample = if content.len > 500: content[0..<500] else: content
    contents.add sample
  
  # Only test first 3 files to keep benchmark reasonable
  let sampleContents = if contents.len > 3: contents[0..<3] else: contents
  
  timeIt "Embedding Generation":
    for content in sampleContents:
      let embedding = generateEmbedding(content)
      keep embedding.len

proc benchmarkFragmentCreation() =
  ## Benchmark fragment creation.
  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  let testFile = if files.len > 0: files[0] else: ""
  if testFile == "":
    echo "No files found for fragment benchmark"
    return
    
  let content = readFile(testFile)
  
  timeIt "Fragment Creation":
    let fragment = newRegenFragment(content, testFile)
    keep fragment.hash

proc benchmarkFileIndexing() =
  ## Benchmark single file indexing.
  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  let testFile = if files.len > 0: files[0] else: ""
  if testFile == "":
    echo "No files found for file indexing benchmark"
    return
  
  timeIt "Single File Index":
    let regenFile = newRegenFile(testFile)
    keep regenFile.hash

proc benchmarkFullIndexing() =
  ## Benchmark full repository indexing.
  timeIt "Full Repo Index", 1:  # Only run once due to embedding generation
    let index = newRegenIndex(regen_git_repo, getCurrentDir(), @WhitelistedExtensions)
    keep index.repo.files.len

proc benchmarkParallelEmbeddings() =
  ## Benchmark embedding generation with different maxInFlight values.
  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  var contents: seq[string] = @[]
  
  # Pre-read files and take smaller samples for embedding tests
  for filePath in files:
    let content = readFile(filePath)
    # Take first 300 chars to make embedding tests faster
    let sample = if content.len > 300: content[0..<300] else: content
    contents.add sample
  
  # Test with reasonable number of samples (limit to 12 for benchmark)
  let testContents = if contents.len > 12: contents[0..<12] else: contents
  echo &"Testing with {testContents.len} text samples"
  
  # Test different maxInFlight values
  let maxInFlightValues = [1, 2, 4, 8, 16]
  
  for maxInFlight in maxInFlightValues:
    let apiName = if maxInFlight == 1: "Sequential (maxInFlight=1)" else: &"Parallel (maxInFlight={maxInFlight})"
    
    # Create API instance with this maxInFlight setting
    var testApi = newOpenAiApi(
      baseUrl = "http://10.11.2.16:11434/v1",
      apiKey = "ollama", 
      maxInFlight = maxInFlight
    )
    
    # Temporarily replace the global API
    let originalApi = localOllamaApi
    localOllamaApi = testApi
    
    timeIt &"Embeddings - {apiName}":
      let embeddings = generateEmbeddingsBatch(testContents)
      keep embeddings.len
    
    # Restore original API
    localOllamaApi = originalApi

proc benchmarkCosineSimilarity() =
  ## Benchmark cosine similarity calculation.
  # Create test embeddings (typical embedding size for nomic-embed-text is 768)
  let embeddingSize = 768
  var embedding1: seq[float32] = @[]
  var embedding2: seq[float32] = @[]
  
  # Generate random embeddings for testing
  for i in 0..<embeddingSize:
    embedding1.add(float32(i) / float32(embeddingSize))
    embedding2.add(float32(i * 2) / float32(embeddingSize))
  
  timeIt "Cosine Similarity (768D vectors)":
    let similarity = cosineSimilarity(embedding1, embedding2)
    keep similarity

proc benchmarkSimilaritySearch() =
  ## Benchmark similarity search performance.
  echo "Setting up similarity search benchmark..."
  
  # Create a test index with multiple files and fragments
  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  let testFiles = if files.len > 5: files[0..<5] else: files  # Limit to 5 files for benchmark
  
  if testFiles.len == 0:
    echo "No files found for similarity search benchmark"
    return
  
  # Create test index with actual content
  var regenFilesTbl = initTable[string, RegenFile]()
  for filePath in testFiles:
    let regenFile = newRegenFile(filePath)
    regenFilesTbl[regenFile.path] = regenFile
  
  let testRepo = RegenGitRepo(
    name: "benchmark-repo",
    latestCommitHash: "test123",
    isDirty: false,
    files: regenFilesTbl
  )
  
  let testIndex = RegenIndex(
    kind: regen_git_repo,
    repo: testRepo
  )
  
  echo &"Index created with {testIndex.repo.files.len} files"
  var totalFragments = 0
  for file in testIndex.repo.files.values:
    totalFragments += file.fragments.len
  echo &"Total fragments: {totalFragments}"
  
  # Test different query types
  let queries = @[
    "function definition",
    "import statement", 
    "error handling",
    "data structure",
    "algorithm implementation"
  ]
  
  for query in queries:
    let queryStr = query  # Copy to avoid capture issues
    timeIt &"Similarity Search: '{queryStr}' (top 5)":
      let results = findSimilarFragments(testIndex, queryStr, maxResults = 5)
      keep results.len
  
  # Test with different result limits
  let resultLimits = [1, 5, 10, 20]
  for limit in resultLimits:
    timeIt &"Similarity Search: top {limit} results":
      let results = findSimilarFragments(testIndex, "function", maxResults = limit)
      keep results.len



proc main() =
  echo &"Benchmarking Regen indexing performance"
  echo &"Repository: {getCurrentDir()}"
  
  let files = findProjectFiles(getCurrentDir(), @WhitelistedExtensions)
  echo &"Files to index: {files.len}"
  
  var totalSize = 0
  for filePath in files:
    totalSize += getFileSize(filePath).int
  echo &"Total content size: {totalSize} bytes"
  echo ""
  
  echo "=== File Operations ==="
  benchmarkFileReading()
  echo ""
  
  echo "=== Hashing ==="
  benchmarkHashing()
  echo ""
  
  echo "=== Fragment Operations ==="
  benchmarkFragmentCreation()
  benchmarkFileIndexing()
  echo ""
  
  echo "=== Embedding Generation ==="
  benchmarkEmbeddings()
  echo ""
  
  echo "=== Sequential vs Parallel Embeddings ==="
  benchmarkParallelEmbeddings()
  echo ""
  
  echo "=== Full Indexing ==="
  benchmarkFullIndexing()
  echo ""
  
  echo "=== Similarity Operations ==="
  benchmarkCosineSimilarity()
  benchmarkSimilaritySearch()
  echo ""
  
  echo "Benchmark complete!"

when isMainModule:
  main() 
