import
  std/unittest,
  fragment

suite "Chunk file selection":
  test "markdown files use markdown chunk algorithm":
    let content = "# Header\n\nBody line\n\n## Section\n\nMore text"
    let chunks = chunkFile("notes.md", content)

    check chunks.len > 0
    for ch in chunks:
      check ch.chunkAlgorithm == "markdown"
