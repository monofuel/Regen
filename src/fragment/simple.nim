import std/[strutils]
import ../types

const
  SoftMaxLines = 120
  MinLines = 40
  MaxSimpleLineChars = 700
  BlobBase64RunChars = 192
  BlobLineMinChars = 256
  BlobMarkers = [
    "certificate-authority-data:",
    "client-certificate-data:",
    "client-key-data:",
    "-----begin ",
    "-----end ",
    "ssh-rsa ",
    "ssh-ed25519 "
  ]

proc makeSimpleFragment(startLine: int, endLine: int): RegenFragment =
  ## Build a simple chunk fragment from a line range.
  result = RegenFragment(
    startLine: startLine,
    endLine: endLine,
    embedding: @[],
    fragmentType: "document",
    model: "",
    chunkAlgorithm: "simple",
    task: RetrievalDocument,
    private: false,
    contentScore: 0,
    hash: ""
  )

proc isBase64LikeChar(ch: char): bool =
  ## Return true when a character is commonly found in base64 payloads.
  result = (
    (ch >= 'A' and ch <= 'Z') or
    (ch >= 'a' and ch <= 'z') or
    (ch >= '0' and ch <= '9') or
    ch == '+' or
    ch == '/' or
    ch == '='
  )

proc hasLongBase64Run(line: string, minRun: int): bool =
  ## Return true when a line contains a long contiguous base64-like sequence.
  var run = 0
  for ch in line:
    if isBase64LikeChar(ch):
      run.inc
      if run >= minRun:
        return true
    else:
      run = 0
  result = false

proc isBlobLikeLine(line: string): bool =
  ## Return true when a line likely contains encoded/binary payload content.
  let trimmed = line.strip()
  if trimmed.len == 0:
    return false
  let lower = trimmed.toLowerAscii()
  for marker in BlobMarkers:
    if marker in lower:
      return true
  if trimmed.len >= BlobLineMinChars and hasLongBase64Run(trimmed, BlobBase64RunChars):
    return true
  result = false

proc chunkSimple*(content: string): seq[RegenFragment] =
  ## Simple line-count-based chunker producing RegenFragments with line ranges only.
  ## Text is not stored here; embeddings will be created upstream using these ranges.
  result = @[]
  let lines = content.split('\n')
  if lines.len == 0:
    return

  var startLine = 1
  var currentCount = 0
  for i in 0 ..< lines.len:
    let line = lines[i]
    let lineNumber = i + 1
    let isLongLine = line.len >= MaxSimpleLineChars
    if isLongLine or isBlobLikeLine(line):
      if startLine <= lineNumber - 1:
        result.add(makeSimpleFragment(startLine, lineNumber - 1))
      result.add(makeSimpleFragment(lineNumber, lineNumber))
      startLine = lineNumber + 1
      currentCount = 0
      continue

    currentCount.inc
    let isBoundary = currentCount >= SoftMaxLines or (currentCount >= MinLines and lines[i].strip().len == 0)
    let isLast = i == lines.len - 1
    if isBoundary or isLast:
      let endLine = i + 1
      result.add(makeSimpleFragment(startLine, endLine))
      startLine = endLine + 1
      currentCount = 0

