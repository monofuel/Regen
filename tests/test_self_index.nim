import
  std/[os, parseopt],
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

const
  WhitelistedExtensions = [".nim", ".md"]
  ProjectRoot = "Fraggy"

proc createSelfIndex(): FraggyIndex =
  ## Create a FraggyIndex of the Fraggy repository itself.
  let projectPath = getCurrentDir() / ProjectRoot
  echo "Creating self-index of Fraggy repository..."
  result = newFraggyIndex(fraggy_git_repo, projectPath, @WhitelistedExtensions)

proc main() =
  ## Main test function that creates the index and compares with gold master.
  let index = createSelfIndex()
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