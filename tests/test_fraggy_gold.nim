import
  std/[strformat, os, parseopt],
  ../src/fraggy

# Parse command line arguments
var updateGold = false
var p = initOptParser()
while true:
  p.next()
  case p.kind
  of cmdEnd: break
  of cmdShortOption, cmdLongOption:
    if p.key == "u" or p.key == "update-gold":
      updateGold = true
  of cmdArgument:
    discard

proc createTestData(): FraggyGitRepo =
  ## Create consistent test data for serialization testing.
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
  
  result = FraggyGitRepo(
    name: "test-repo",
    latestCommitHash: "abc123def456",
    files: @[file1, file2]
  )

const
  tmpFile = "tests/tmp/test_fraggy_gold.flat"
  goldFile = "tests/gold/test_fraggy_gold.flat"

# Create test data and serialize to tmp file
let testRepo = createTestData()

# Create tmp directory if it doesn't exist
createDir(tmpFile.parentDir)

# Clean up any existing test file
if fileExists(tmpFile):
  removeFile(tmpFile)

# Serialize to tmp file
writeRepoToFile(testRepo, tmpFile)

# Update gold file if flag is set
if updateGold:
  createDir(goldFile.parentDir)
  if fileExists(goldFile):
    removeFile(goldFile)
  copyFile(tmpFile, goldFile)
  echo "✅ Updated gold file: ", goldFile
  removeFile(tmpFile)
  quit(0)

# Now compare with gold file
if not fileExists(goldFile):
  echo "Gold file doesn't exist: ", goldFile
  echo "Run with -u or --update-gold to create it"
  removeFile(tmpFile)
  quit(1)

let
  tmpContent = readFile(tmpFile)
  goldContent = readFile(goldFile)

# Clean up tmp file
removeFile(tmpFile)

if tmpContent == goldContent:
  echo "✅ Test passed: Fraggy binary serialization matches gold file"
  
  # Also verify we can deserialize both files successfully
  let deserializedFromGold = readRepoFromFile(goldFile)
  let testMatches = (
    deserializedFromGold.name == testRepo.name and
    deserializedFromGold.latestCommitHash == testRepo.latestCommitHash and
    deserializedFromGold.files.len == testRepo.files.len
  )
  
  if testMatches:
    echo "✅ Deserialization verification: PASS"
  else:
    echo "❌ Deserialization verification: FAIL"
    quit(1)
else:
  echo "❌ Test failed: Fraggy binary serialization differs from gold file"
  echo &"Gold file size: {goldContent.len} bytes"
  echo &"Test file size: {tmpContent.len} bytes"
  
  # Show byte-level differences for first few bytes
  echo "First 50 bytes comparison:"
  let maxBytes = min(50, min(goldContent.len, tmpContent.len))
  for i in 0..<maxBytes:
    if goldContent[i] != tmpContent[i]:
      echo &"Byte {i}: gold={ord(goldContent[i])} test={ord(tmpContent[i])}"
  
  echo "\nRun with -u or --update-gold to update the gold file"
  quit(1) 