import std/[os, tables, endians, strformat]
import src/[types, logs]
import flatty

const RegenFileIndexVersion = 8
const ConfigVersion = "0.1.0"

proc writeIndexToFile(index: RegenIndex, filepath: string) =
  ## Write a RegenIndex object to a file using flatty serialization with version prefix.
  let data = toFlatty(index)
  var versionBytes: array[4, byte]
  var versionInt = RegenFileIndexVersion
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
  if fileVersion < RegenFileIndexVersion:
    # Older version - for now, we require reindexing
    raise newException(ValueError, &"Index file {filepath} has version {fileVersion} but current version is {RegenFileIndexVersion}. Please reindex.")
  elif fileVersion > RegenFileIndexVersion:
    # Newer version - this shouldn't happen unless there's a bug
    echo &"Warning: Index file {filepath} has newer version {fileVersion} than expected {RegenFileIndexVersion}. This may cause issues."

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
    version: ConfigVersion,
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
  echo "✓ Test completed successfully"

when isMainModule:
  testVersioning()
