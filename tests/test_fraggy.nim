import
  unittest,
  ../src/regen

from std/os import fileExists, removeFile

suite "RegenIndex serialization tests":

  test "can serialize and deserialize RegenIndex with git repo":
    # Create dummy fragments with real embeddings
    let fragment1 = RegenFragment(
      startLine: 1,
      endLine: 10,
      embedding: generateEmbedding("def calculate_sum(a, b):\n    return a + b"),
      fragmentType: "function",
      model: SimilarityEmbeddingModel,
      private: false,
      contentScore: 85,
      hash: "frag1hash"
    )
    
    let fragment2 = RegenFragment(
      startLine: 11,
      endLine: 20,
      embedding: generateEmbedding("# This function calculates the sum of two numbers"),
      fragmentType: "comment",
      model: SimilarityEmbeddingModel,
      private: false,
      contentScore: 60,
      hash: "frag2hash"
    )
    
    # Create dummy files
    let file1 = RegenFile(
      path: "/src/main.nim",
      filename: "main.nim",
      hash: "file1hash",
      creationTime: 1640995200.0,
      lastModified: 1640995200.0,
      fragments: @[fragment1, fragment2]
    )
    
    let file2 = RegenFile(
      path: "/src/utils.nim",
      filename: "utils.nim",
      hash: "file2hash",
      creationTime: 1640995300.0,
      lastModified: 1640995300.0,
      fragments: @[]  # Empty file
    )
    
    # Create test repo
    let testRepo = RegenGitRepo(
      name: "test-repo",
      latestCommitHash: "abc123def456",
      isDirty: false,
      files: @[file1, file2]
    )
    
    # Create test index
    let testIndex = RegenIndex(
      version: "0.1.0",
      kind: regen_git_repo,
      repo: testRepo
    )
    
    let testFile = "test_index.flat"
    
    # Clean up any existing test file
    if fileExists(testFile):
      removeFile(testFile)
    
    # Serialize to file
    writeIndexToFile(testIndex, testFile)
    
    # Verify file was created
    check fileExists(testFile)
    
    # Deserialize from file
    let loadedIndex = readIndexFromFile(testFile)
    
    # Verify the index data matches
    check loadedIndex.version == testIndex.version
    check loadedIndex.kind == testIndex.kind
    check loadedIndex.repo.name == testRepo.name
    check loadedIndex.repo.latestCommitHash == testRepo.latestCommitHash
    check loadedIndex.repo.isDirty == testRepo.isDirty
    check loadedIndex.repo.files.len == testRepo.files.len
    
    # Verify first file
    check loadedIndex.repo.files[0].filename == file1.filename
    check loadedIndex.repo.files[0].hash == file1.hash
    check loadedIndex.repo.files[0].fragments.len == 2
    
    # Verify first fragment - including the embedding
    check loadedIndex.repo.files[0].fragments[0].startLine == fragment1.startLine
    check loadedIndex.repo.files[0].fragments[0].endLine == fragment1.endLine
    check loadedIndex.repo.files[0].fragments[0].fragmentType == fragment1.fragmentType
    check loadedIndex.repo.files[0].fragments[0].model == fragment1.model
    check loadedIndex.repo.files[0].fragments[0].embedding.len == fragment1.embedding.len
    check loadedIndex.repo.files[0].fragments[0].embedding == fragment1.embedding
    
    # Verify second file (empty)
    check loadedIndex.repo.files[1].filename == file2.filename
    check loadedIndex.repo.files[1].fragments.len == 0
    
    # Clean up test file
    removeFile(testFile)

  test "can serialize and deserialize RegenIndex with folder":
    # Create a simple folder index with real embedding
    let file1 = RegenFile(
      path: "/data/docs/readme.md",
      filename: "readme.md",
      hash: "readmehash",
      creationTime: 1640995400.0,
      lastModified: 1640995400.0,
      fragments: @[
        RegenFragment(
          startLine: 1,
          endLine: 5,
          embedding: generateEmbedding("# Project README\n\nThis is a sample project documentation."),
          fragmentType: "markdown_header",
          model: SimilarityEmbeddingModel,
          private: false,
          contentScore: 90,
          hash: "readme_frag_hash"
        )
      ]
    )
    
    let testFolder = RegenFolder(
      path: "/data/docs",
      files: @[file1]
    )
    
    let testIndex = RegenIndex(
      version: "0.1.0",
      kind: regen_folder,
      folder: testFolder
    )
    
    let testFile = "test_folder_index.flat"
    
    # Clean up any existing test file
    if fileExists(testFile):
      removeFile(testFile)
    
    # Serialize to file
    writeIndexToFile(testIndex, testFile)
    
    # Verify file was created
    check fileExists(testFile)
    
    # Deserialize from file
    let loadedIndex = readIndexFromFile(testFile)
    
    # Verify the index data matches
    check loadedIndex.version == testIndex.version
    check loadedIndex.kind == testIndex.kind
    check loadedIndex.folder.path == testFolder.path
    check loadedIndex.folder.files.len == testFolder.files.len
    check loadedIndex.folder.files[0].filename == file1.filename
    check loadedIndex.folder.files[0].fragments.len == 1
    check loadedIndex.folder.files[0].fragments[0].embedding.len > 0
    
    # Clean up test file
    removeFile(testFile)

suite "Similarity search tests":

  test "cosine similarity calculation":
    # Test identical vectors
    let vec1 = @[1.0'f32, 0.0'f32, 0.0'f32]
    let vec2 = @[1.0'f32, 0.0'f32, 0.0'f32]
    check cosineSimilarity(vec1, vec2) == 1.0'f32
    
    # Test orthogonal vectors
    let vec3 = @[1.0'f32, 0.0'f32, 0.0'f32]
    let vec4 = @[0.0'f32, 1.0'f32, 0.0'f32]
    check cosineSimilarity(vec3, vec4) == 0.0'f32
    
    # Test opposite vectors
    let vec5 = @[1.0'f32, 0.0'f32, 0.0'f32]
    let vec6 = @[-1.0'f32, 0.0'f32, 0.0'f32]
    check cosineSimilarity(vec5, vec6) == -1.0'f32
    
    # Test partial similarity
    let vec7 = @[1.0'f32, 1.0'f32, 0.0'f32]
    let vec8 = @[1.0'f32, 0.0'f32, 0.0'f32]
    let similarity = cosineSimilarity(vec7, vec8)
    check abs(similarity - 0.7071067) < 0.0001  # Should be 1/sqrt(2) ≈ 0.7071

  test "similarity search with git repo index":
    # Create test fragments with known embeddings
    let fragment1 = RegenFragment(
      startLine: 1,
      endLine: 10,
      embedding: generateEmbedding("function to calculate sum of two numbers"),
      fragmentType: "function",
      model: SimilarityEmbeddingModel,
      private: false,
      contentScore: 85,
      hash: "frag1hash"
    )
    
    let fragment2 = RegenFragment(
      startLine: 11,
      endLine: 20,
      embedding: generateEmbedding("function to calculate product of two numbers"),
      fragmentType: "function",
      model: SimilarityEmbeddingModel,
      private: false,
      contentScore: 80,
      hash: "frag2hash"
    )
    
    let fragment3 = RegenFragment(
      startLine: 21,
      endLine: 30,
      embedding: generateEmbedding("user interface component for displaying buttons"),
      fragmentType: "component",
      model: SimilarityEmbeddingModel,
      private: false,
      contentScore: 70,
      hash: "frag3hash"
    )
    
    # Create test file
    let testFile = RegenFile(
      path: "/src/math.nim",
      filename: "math.nim",
      hash: "mathfilehash",
      creationTime: 1640995200.0,
      lastModified: 1640995200.0,
      fragments: @[fragment1, fragment2, fragment3]
    )
    
    # Create test repo
    let testRepo = RegenGitRepo(
      name: "test-repo",
      latestCommitHash: "abc123def456",
      isDirty: false,
      files: @[testFile]
    )
    
    # Create test index
    let testIndex = RegenIndex(
      version: "0.1.0",
      kind: regen_git_repo,
      repo: testRepo
    )
    
    # Test similarity search for math-related query
    let mathResults = findSimilarFragments(testIndex, "addition of numbers", maxResults = 5)
    check mathResults.len > 0
    check mathResults[0].similarity > 0.0  # Should find some similarity
    
    # The first result should be the sum function (fragment1) since it's most similar
    # to "addition of numbers"
    check mathResults[0].fragment.hash == "frag1hash"
    
    # Test similarity search for UI-related query
    let uiResults = findSimilarFragments(testIndex, "button component interface", maxResults = 5)
    check uiResults.len > 0
    
    # The UI fragment should be most similar to the UI query
    check uiResults[0].fragment.hash == "frag3hash"
    
    # Test with max results limit
    let limitedResults = findSimilarFragments(testIndex, "calculate", maxResults = 2)
    check limitedResults.len <= 2

  test "similarity search with folder index":
    # Create a test fragment
    let fragment = RegenFragment(
      startLine: 1,
      endLine: 5,
      embedding: generateEmbedding("project documentation and setup instructions"),
      fragmentType: "markdown_header",
      model: SimilarityEmbeddingModel,
      private: false,
      contentScore: 90,
      hash: "readme_frag_hash"
    )
    
    let testFile = RegenFile(
      path: "/docs/readme.md",
      filename: "readme.md",
      hash: "readmehash",
      creationTime: 1640995400.0,
      lastModified: 1640995400.0,
      fragments: @[fragment]
    )
    
    let testFolder = RegenFolder(
      path: "/docs",
      files: @[testFile]
    )
    
    let testIndex = RegenIndex(
      version: "0.1.0",
      kind: regen_folder,
      folder: testFolder
    )
    
    # Test similarity search
    let results = findSimilarFragments(testIndex, "how to setup the project", maxResults = 5)
    check results.len > 0
    check results[0].similarity > 0.0
    check results[0].file.filename == "readme.md"
