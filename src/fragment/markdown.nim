import std/[strutils]
import ../types

const
  MaxHeaderSectionLines = 120
  MinHeaderSectionLines = 10
  MaxMarkdownLineChars = 700
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

proc flushSection(result: var seq[RegenFragment], sectionStart: int, sectionEnd: int) =
  ## Append a markdown section fragment for the given line range.
  if sectionStart <= 0 or sectionEnd < sectionStart:
    return
  result.add(RegenFragment(
    startLine: sectionStart,
    endLine: sectionEnd,
    embedding: @[],
    fragmentType: "markdown_section",
    model: "",
    chunkAlgorithm: "markdown",
    task: RetrievalDocument,
    private: false,
    contentScore: 0,
    hash: ""
  ))

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

proc chunkMarkdown*(content: string): seq[RegenFragment] =
  ## Markdown-aware chunker.
  ## - Splits at ATX headers (#, ##, ###, ...)
  ## - Keeps lists contiguous within their header section.
  ## - Caps section length to MaxHeaderSectionLines.
  ## - Isolates very long lines and blob-like payload lines to avoid oversized embedding chunks.
  result = @[]
  let lines = content.split('\n')
  if lines.len == 0:
    return

  var sectionStart = 1
  var currentLen = 0
  for i, line in lines:
    let lineNumber = i + 1
    let isLongLine = line.len >= MaxMarkdownLineChars
    if isLongLine or isBlobLikeLine(line):
      flushSection(result, sectionStart, lineNumber - 1)
      flushSection(result, lineNumber, lineNumber)
      sectionStart = lineNumber + 1
      currentLen = 0
      continue

    let isHeader = line.len > 0 and line.strip().startsWith('#')
    let isLast = i == lines.len - 1
    currentLen.inc

    if (isHeader and i != 0):
      # Close previous section right before this header
      flushSection(result, sectionStart, i)
      sectionStart = i + 1
      currentLen = 1
      continue

    if currentLen >= MaxHeaderSectionLines:
      flushSection(result, sectionStart, i + 1)
      sectionStart = i + 2
      currentLen = 0

    if isLast:
      flushSection(result, sectionStart, i + 1)

