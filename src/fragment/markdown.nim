import std/[strutils]
import ../types

const
  MaxHeaderSectionLines = 120
  MinHeaderSectionLines = 10

proc flushSection(result: var seq[RegenFragment], sectionStart: int, sectionEnd: int) =
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

proc chunkMarkdown*(content: string): seq[RegenFragment] =
  ## Markdown-aware chunker.
  ## - Splits at ATX headers (#, ##, ###, ...)
  ## - Keeps lists contiguous within their header section.
  ## - Caps section length to MaxHeaderSectionLines.
  result = @[]
  let lines = content.split('\n')
  if lines.len == 0:
    return

  var sectionStart = 1
  var currentLen = 0
  for i, line in lines:
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


