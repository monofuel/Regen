import
  std/[os, unittest],
  ../src/fraggy

suite "GitRepo serialization tests":

  test "can serialize and deserialize GitRepo":
    let testRepo = GitRepo(
      name: "test-repo",
      latestCommitHash: "abc123def456"
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
    
    # Verify the data matches
    check loadedRepo.name == testRepo.name
    check loadedRepo.latestCommitHash == testRepo.latestCommitHash
    
    # Clean up test file
    removeFile(testFile)
