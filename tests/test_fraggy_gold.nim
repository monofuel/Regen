import
  std/[strutils, strformat, os, parseopt],
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

proc fragmentToString(fragment: FraggyFragment): string =
  ## Convert a FraggyFragment to a readable string representation.
  result = &"Fragment(startLine: {fragment.startLine}, endLine: {fragment.endLine}, "
  result.add &"embedding: [{fragment.embedding.join(\", \")}], "
  result.add &"fragmentType: \"{fragment.fragmentType}\", model: \"{fragment.model}\", "
  result.add &"private: {fragment.private}, contentScore: {fragment.contentScore}, "
  result.add &"hash: \"{fragment.hash}\")"

proc fileToString(file: FraggyFile): string =
  ## Convert a FraggyFile to a readable string representation.
  result = &"File(hostname: \"{file.hostname}\", path: \"{file.path}\", "
  result.add &"filename: \"{file.filename}\", hash: \"{file.hash}\", "
  result.add &"creationTime: {file.creationTime}, lastModified: {file.lastModified}, "
  result.add &"fragments: [\n"
  for i, fragment in file.fragments:
    result.add &"    {fragmentToString(fragment)}"
    if i < file.fragments.len - 1:
      result.add ","
    result.add "\n"
  result.add "  ])"

proc repoToString(repo: FraggyGitRepo): string =
  ## Convert a FraggyGitRepo to a readable string representation.
  result = &"GitRepo(name: \"{repo.name}\", latestCommitHash: \"{repo.latestCommitHash}\", "
  result.add &"files: [\n"
  for i, file in repo.files:
    let fileStr = fileToString(file).replace("\n", "\n  ")
    result.add &"  {fileStr}"
    if i < repo.files.len - 1:
      result.add ","
    result.add "\n"
  result.add "])"

proc generateSerializationReport(): string =
  ## Generate a report of the serialization/deserialization process.
  # Create test data
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
  
  let originalRepo = FraggyGitRepo(
    name: "test-repo",
    latestCommitHash: "abc123def456",
    files: @[file1, file2]
  )
  
  result = "# Fraggy Serialization Gold Master Test\n\n"
  result.add "## Original Data Structure\n"
  result.add "```\n"
  result.add repoToString(originalRepo)
  result.add "\n```\n\n"
  
  # Serialize and deserialize
  let testFile = "tests/tmp/test_serialization.flat"
  createDir(testFile.parentDir)
  
  # Clean up any existing test file
  if fileExists(testFile):
    removeFile(testFile)
  
  writeRepoToFile(originalRepo, testFile)
  let deserializedRepo = readRepoFromFile(testFile)
  
  # Clean up test file
  removeFile(testFile)
  
  result.add "## Deserialized Data Structure\n"
  result.add "```\n"
  result.add repoToString(deserializedRepo)
  result.add "\n```\n\n"
  
  # Verification
  let matches = (
    deserializedRepo.name == originalRepo.name and
    deserializedRepo.latestCommitHash == originalRepo.latestCommitHash and
    deserializedRepo.files.len == originalRepo.files.len
  )
  
  result.add &"## Verification\n"
  result.add &"Round-trip serialization: {(if matches: \"PASS\" else: \"FAIL\")}\n"
  result.add &"File count: {deserializedRepo.files.len}\n"
  
  if deserializedRepo.files.len > 0:
    result.add &"First file fragments: {deserializedRepo.files[0].fragments.len}\n"
  if deserializedRepo.files.len > 1:
    result.add &"Second file fragments: {deserializedRepo.files[1].fragments.len}\n"

const
  tmpFile = "tests/tmp/test_fraggy_gold.txt"
  goldFile = "tests/gold/test_fraggy_gold.txt"

let output = generateSerializationReport()

# Create tmp directory if it doesn't exist
createDir(tmpFile.parentDir)
writeFile(tmpFile, output)

# Update gold file if flag is set
if updateGold:
  createDir(goldFile.parentDir)
  writeFile(goldFile, output)
  echo "✅ Updated gold file: ", goldFile
  quit(0)

# Now compare with gold file
if not fileExists(goldFile):
  echo "Gold file doesn't exist: ", goldFile
  echo "Run with -u or --update-gold to create it"
  quit(1)

let
  tmpContent = readFile(tmpFile)
  goldContent = readFile(goldFile)

if tmpContent == goldContent:
  echo "✅ Test passed: Fraggy serialization output matches gold file"
else:
  echo "❌ Test failed: Fraggy serialization output differs from gold file"
  echo "--- Diff ---"
  
  # Create a simple diff
  let
    tmpLines = tmpContent.splitLines()
    goldLines = goldContent.splitLines()
    maxLines = max(tmpLines.len, goldLines.len)
  
  for i in 0..<maxLines:
    if i >= tmpLines.len:
      echo &"Line {i+1}: [missing] | {goldLines[i]}"
    elif i >= goldLines.len:
      echo &"Line {i+1}: {tmpLines[i]} | [missing]"
    elif tmpLines[i] != goldLines[i]:
      echo &"Line {i+1}: {tmpLines[i]} | {goldLines[i]}"
  
  echo "\nRun with -u or --update-gold to update the gold file"
  quit(1) 