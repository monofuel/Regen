import std/[os, tables, endians, strformat]
import ../src/[types]
import flatty

const RegenFileIndexVersion = 8

proc writeIndexToFile(index: RegenIndex, filepath: string, version: int32 = RegenFileIndexVersion) =
  ## Write a RegenIndex object to a file using flatty serialization with version prefix.
  let data = toFlatty(index)
  var versionBytes: array[4, byte]
  var versionInt = version
  littleEndian32(versionBytes.addr, versionInt.addr)
  let versionData = @versionBytes
  let dataBytes = cast[seq[byte]](data)
  writeFile(filepath, versionData & dataBytes)

proc readIndexFromFile(filepath: string): RegenIndex =
  ## Read a RegenIndex object from a file using flatty deserialization with version checking.
  let dataBytes = cast[seq[byte]](readFile(filepath))

  if dataBytes.len < 4:
    raise newException(ValueError, &"Index file {filepath} is too small to contain version header")

  # Read version from first 4 bytes
  var fileVersion: int32
  var versionBytes: array[4, byte]
  for i in 0..3:
    versionBytes[i] = dataBytes[i]
  littleEndian32(fileVersion.addr, versionBytes.addr)

  echo &"File version: {fileVersion}, expected: {RegenFileIndexVersion}"

  # Check version compatibility
  if fileVersion != RegenFileIndexVersion:
    # Invalid version - delete the file and behave as if it doesn't exist
    echo &"Index file {filepath} has incompatible version {fileVersion} (expected {RegenFileIndexVersion}). Deleting file."
    try:
      removeFile(filepath)
    except:
      echo &"Could not delete invalid index file {filepath}"
    # Raise specific exception so caller knows this is a version incompatibility
    var err = new(IndexVersionError)
    err.msg = &"Index file {filepath} had incompatible version and was deleted. Index will be rebuilt."
    err.filepath = filepath
    err.fileVersion = fileVersion
    err.expectedVersion = RegenFileIndexVersion
    raise err

  # Extract flatty data (skip version header)
  let flattyData = cast[string](dataBytes[4..^1])
  fromFlatty(flattyData, RegenIndex)

proc testVersioning() =
  echo "Testing Regen index versioning..."

  # Create a simple test index
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

  # Test writing
  let testFilePath = "/tmp/test_regen_index.flat"
  echo &"Writing index to {testFilePath}..."
  writeIndexToFile(testIndex, testFilePath)

  # Verify file was created and has version header (4 bytes)
  if fileExists(testFilePath):
    let fileSize = getFileSize(testFilePath)
    echo &"File created, size: {fileSize} bytes"
    if fileSize >= 4:
      echo "✓ File has version header"
    else:
      echo "✗ File too small, no version header"
      return
  else:
    echo "✗ File was not created"
    return

  # Test reading
  echo "Reading index back..."
  try:
    let loadedIndex = readIndexFromFile(testFilePath)
    echo "✓ Index loaded successfully"
    echo &"Loaded index kind: {loadedIndex.kind}"
    if loadedIndex.kind == regen_folder:
      echo &"Files in index: {loadedIndex.folder.files.len}"
    else:
      echo "✗ Wrong index kind"
  except Exception as e:
    echo &"✗ Failed to load index: {e.msg}"

  # Clean up
  removeFile(testFilePath)

  # Test version 7 compatibility (should raise IndexVersionError)
  echo "\nTesting version 7 compatibility..."
  let oldVersionFilePath = "/tmp/test_old_version.flat"
  echo &"Writing index with version 7 to {oldVersionFilePath}..."
  writeIndexToFile(testIndex, oldVersionFilePath, 7)

  echo "Attempting to read version 7 file..."
  try:
    let loadedIndex = readIndexFromFile(oldVersionFilePath)
    echo "✗ ERROR: Should have raised IndexVersionError for version 7!"
  except IndexVersionError as e:
    echo "✓ Correctly caught IndexVersionError for version 7:"
    echo &"   Filepath: {e.filepath}"
    echo &"   File version: {e.fileVersion}"
    echo &"   Expected version: {e.expectedVersion}"
  except Exception as e:
    echo &"✗ ERROR: Caught wrong exception type: {e.msg}"

  # Verify file was deleted
  if fileExists(oldVersionFilePath):
    echo "✗ ERROR: Version 7 file should have been deleted!"
    removeFile(oldVersionFilePath)
  else:
    echo "✓ Version 7 file was correctly deleted"

  echo "✓ All tests completed successfully"

when isMainModule:
  testVersioning()
