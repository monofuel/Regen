import
  std/[os, parseopt, strformat],
  ../src/regen

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

const
  WhitelistedExtensions = [".nim", ".md"]

proc validateGitCommitHash(hash: string): bool =
  ## Validate that a git commit hash is a proper 40-character hex string.
  if hash == "unknown":
    return false
  if hash.len != 40:
    return false
  for c in hash:
    if c notin {'0'..'9', 'a'..'f', 'A'..'F'}:
      return false
  return true

proc createSelfIndex(): RegenIndex =
  ## Create a RegenIndex of the Regen repository itself.
  let projectPath = getCurrentDir()  # We're already in the Regen directory
  echo "Creating self-index of Regen repository..."
  result = newRegenIndex(regen_git_repo, projectPath, @WhitelistedExtensions)

proc main() =
  ## Main test function that creates the index and compares with gold master.
  let index = createSelfIndex()
  
  # Validate that we have a proper git commit hash
  if index.kind == regen_git_repo:
    let commitHash = index.repo.latestCommitHash
    if not validateGitCommitHash(commitHash):
      echo &"✗ Invalid git commit hash: '{commitHash}'"
      echo "Expected a 40-character hexadecimal git commit hash"
      quit(1)
    echo &"✓ Valid git commit hash: {commitHash}"
  
  let tmpDir = "tests/tmp"
  let goldDir = "tests/gold"
  let outputFile = tmpDir / "self_index.flat"
  let goldFile = goldDir / "self_index.flat"
  
  # Ensure tmp directory exists
  createDir(tmpDir)
  
  # Write the index to a temporary file
  writeIndexToFile(index, outputFile)
  
  if updateGold:
    echo "Updating gold master..."
    createDir(goldDir)
    copyFile(outputFile, goldFile)
    echo "Gold master updated successfully"
  else:
    if fileExists(goldFile):
      let goldData = readFile(goldFile)
      let testData = readFile(outputFile)
      
      if goldData == testData:
        echo "✓ Self-index test passed - output matches gold master"
      else:
        echo "✗ Self-index test failed - output differs from gold master"
        echo "Run with -u to update the gold master if this change is expected"
        quit(1)
    else:
      echo "No gold master found. Run with -u to create initial gold master"
      quit(1)

when isMainModule:
  main() 
