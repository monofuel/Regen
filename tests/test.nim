import
  unittest,
  ../src/fraggy

from std/os import fileExists, removeFile

suite "FraggyIndex serialization tests":

  test "can serialize and deserialize FraggyIndex with git repo":
    # Create dummy fragments with real embeddings
    let fragment1 = FraggyFragment(
      startLine: 1,
      endLine: 10,
      embedding: generateEmbedding("def calculate_sum(a, b):\n    return a + b"),
      fragmentType: "function",
      model: SimilarityEmbeddingModel,
      private: false,
      contentScore: 85,
      hash: "frag1hash"
    )
    
    let fragment2 = FraggyFragment(
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
    let file1 = FraggyFile(
      hostname: "localhost",
      path: "/src/main.nim",
      filename: "main.nim",
      hash: "file1hash",
      creationTime: 1640995200.0,
      lastModified: 1640995200.0,
      fragments: @[fragment1, fragment2]
    )
    
    let file2 = FraggyFile(
      hostname: "localhost", 
      path: "/src/utils.nim",
      filename: "utils.nim",
      hash: "file2hash",
      creationTime: 1640995300.0,
      lastModified: 1640995300.0,
      fragments: @[]  # Empty file
    )
    
    # Create test repo
    let testRepo = FraggyGitRepo(
      name: "test-repo",
      latestCommitHash: "abc123def456",
      isDirty: false,
      files: @[file1, file2]
    )
    
    # Create test index
    let testIndex = FraggyIndex(
      version: "0.1.0",
      kind: fraggy_git_repo,
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

  test "can serialize and deserialize FraggyIndex with folder":
    # Create a simple folder index with real embedding
    let file1 = FraggyFile(
      hostname: "localhost",
      path: "/data/docs/readme.md",
      filename: "readme.md",
      hash: "readmehash",
      creationTime: 1640995400.0,
      lastModified: 1640995400.0,
      fragments: @[
        FraggyFragment(
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
    
    let testFolder = FraggyFolder(
      path: "/data/docs",
      files: @[file1]
    )
    
    let testIndex = FraggyIndex(
      version: "0.1.0",
      kind: fraggy_folder,
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
