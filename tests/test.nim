import
  unittest,
  ../src/fraggy

from std/os import fileExists, removeFile

suite "FraggyGitRepo serialization tests":

  test "can serialize and deserialize FraggyGitRepo with files and fragments":
    # Create dummy fragments
    let fragment1 = FraggyFragment(
      startLine: 1,
      endLine: 10,
      embedding: @[0.1, 0.2, 0.3, 0.4],
      fragmentType: "function",
      model: "nomic-embed-text",
      private: false,
      contentScore: 85,
      hash: "frag1hash"
    )
    
    let fragment2 = FraggyFragment(
      startLine: 11,
      endLine: 20,
      embedding: @[0.5, 0.6, 0.7, 0.8],
      fragmentType: "comment",
      model: "nomic-embed-text",
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
    
    # Create test repo with files
    let testRepo = FraggyGitRepo(
      name: "test-repo",
      latestCommitHash: "abc123def456",
      files: @[file1, file2]
    )
    
    let testFile = "test_repo.flat"
    
    # Clean up any existing test file
    if fileExists(testFile):
      removeFile(testFile)
    
    # Serialize to file
    writeRepoToFile(testRepo, testFile)
    
    # Verify file was created
    check fileExists(testFile)
    
    # Deserialize from file
    let loadedRepo = readRepoFromFile(testFile)
    
    # Verify the repo data matches
    check loadedRepo.name == testRepo.name
    check loadedRepo.latestCommitHash == testRepo.latestCommitHash
    check loadedRepo.files.len == testRepo.files.len
    
    # Verify first file
    check loadedRepo.files[0].filename == file1.filename
    check loadedRepo.files[0].hash == file1.hash
    check loadedRepo.files[0].fragments.len == 2
    
    # Verify first fragment
    check loadedRepo.files[0].fragments[0].startLine == fragment1.startLine
    check loadedRepo.files[0].fragments[0].endLine == fragment1.endLine
    check loadedRepo.files[0].fragments[0].fragmentType == fragment1.fragmentType
    check loadedRepo.files[0].fragments[0].embedding == fragment1.embedding
    
    # Verify second file (empty)
    check loadedRepo.files[1].filename == file2.filename
    check loadedRepo.files[1].fragments.len == 0
    
    # Clean up test file
    removeFile(testFile)
