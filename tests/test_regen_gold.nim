import
  std/[strformat, os, parseopt, tables],
  regen

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

proc createTestData(): RegenIndex =
  ## Create consistent test data for serialization testing.
  let fragment1 = RegenFragment(
    startLine: 1,
    endLine: 10,
    embedding: generateEmbedding("def calculate_sum(a, b):\n    return a + b", SimilarityEmbeddingModel, SemanticSimilarity),
    fragmentType: "function",
    model: SimilarityEmbeddingModel,
    task: SemanticSimilarity,
    private: false,
    contentScore: 85,
    hash: "frag1hash"
  )

  let fragment2 = RegenFragment(
    startLine: 11,
    endLine: 20,
    embedding: generateEmbedding("# This function calculates the sum of two numbers", SimilarityEmbeddingModel, SemanticSimilarity),
    fragmentType: "comment",
    model: SimilarityEmbeddingModel,
    task: SemanticSimilarity,
    private: false,
    contentScore: 60,
    hash: "frag2hash"
  )
  
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
  
  let testRepo = RegenGitRepo(
    path: "/",
    name: "test-repo",
    latestCommitHash: "abc123def456",
    isDirty: false,
    files: {
      "/src/main.nim": file1,
      "/src/utils.nim": file2
    }.toTable
  )
  
  result = RegenIndex(
    kind: regen_git_repo,
    repo: testRepo
  )

const
  tmpFile = "tests/tmp/test_regen_gold.flat"
  goldFile = "tests/gold/test_regen_gold.flat"

# Create test data and serialize to tmp file
let testIndex = createTestData()

# Create tmp directory if it doesn't exist
createDir(tmpFile.parentDir)

# Clean up any existing test file
if fileExists(tmpFile):
  removeFile(tmpFile)

# Serialize to tmp file
writeIndexToFile(testIndex, tmpFile)

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
  echo "✅ Test passed: Regen binary serialization matches gold file"
  
  # Also verify we can deserialize both files successfully
  let deserializedFromGold = readIndexFromFile(goldFile)
  let testMatches = (
    deserializedFromGold.kind == testIndex.kind and
    deserializedFromGold.repo.name == testIndex.repo.name and
    deserializedFromGold.repo.latestCommitHash == testIndex.repo.latestCommitHash and
    deserializedFromGold.repo.files.len == testIndex.repo.files.len and
    deserializedFromGold.repo.files["/src/main.nim"].fragments.len == testIndex.repo.files["/src/main.nim"].fragments.len and
    deserializedFromGold.repo.files["/src/main.nim"].fragments[0].embedding.len == testIndex.repo.files["/src/main.nim"].fragments[0].embedding.len
  )
  
  if testMatches:
    echo "✅ Deserialization verification: PASS"
    echo &"✅ Embedding dimensions: {deserializedFromGold.repo.files[\"/src/main.nim\"].fragments[0].embedding.len}"
  else:
    echo "❌ Deserialization verification: FAIL"
    quit(1)
else:
  echo "❌ Test failed: Regen binary serialization differs from gold file"
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
