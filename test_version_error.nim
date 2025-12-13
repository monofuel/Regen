import std/[os, tables, endians, strformat]
import src/[types, logs, index]
import flatty

const RegenFileIndexVersion = 8

proc writeIndexToFile(index: RegenIndex, filepath: string) =
  ## Write a RegenIndex object to a file using flatty serialization with version prefix.
  let data = toFlatty(index)
  var versionBytes: array[4, byte]
  var versionInt = int32(999)  # Wrong version!
  littleEndian32(versionBytes.addr, versionInt.addr)
  let versionData = @versionBytes
  let dataBytes = cast[seq[byte]](data)
  writeFile(filepath, versionData & dataBytes)

proc testVersionError() =
  echo "Testing IndexVersionError handling..."

  # Create a test index
  let testFile = RegenFile(
    path: "/test/file.nim",
    filename: "file.nim",
    hash: "testhash",
    creationTime: 1234567890.0,
    lastModified: 1234567890.0,
    fragments: @[]
  )

  let testFolder = RegenFolder(
    path: "/test",
    files: {"file.nim": testFile}.toTable
  )

  let testIndex = RegenIndex(
    kind: regen_folder,
    folder: testFolder
  )

  # Write index with wrong version
  let testFilePath = "/tmp/test_wrong_version.flat"
  echo &"Writing index with wrong version to {testFilePath}..."
  writeIndexToFile(testIndex, testFilePath)

  # Try to read it back - should raise IndexVersionError and delete file
  echo "Attempting to read index with wrong version..."
  try:
    let loadedIndex = readIndexFromFile(testFilePath)
    echo "❌ ERROR: Should have raised IndexVersionError!"
  except IndexVersionError as e:
    echo &"✅ Correctly caught IndexVersionError: {e.msg}"
    echo &"   Filepath: {e.filepath}"
    echo &"   File version: {e.fileVersion}"
    echo &"   Expected version: {e.expectedVersion}"
  except Exception as e:
    echo &"❌ ERROR: Caught wrong exception type: {e.msg}"

  # Verify file was deleted
  if fileExists(testFilePath):
    echo "❌ ERROR: File should have been deleted!"
    removeFile(testFilePath)
  else:
    echo "✅ File was correctly deleted"

  echo "✅ Test completed successfully"

when isMainModule:
  testVersionError()
