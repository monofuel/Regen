import
  std/[strutils, os],
  ./types,
  ./fragment/simple,
  ./fragment/markdown,
  ./fragment/nimlang

const
  MarkdownExts = @[".md", ".markdown"]
  NimExts = @[".nim", ".nims"]

proc chunkFile*(filePath: string, content: string): seq[RegenFragment] =
  ## Produce line-range fragments for a file. based on extension.
  let (_, _, ext) = splitFile(filePath)
  let lowerExt = ext.toLower

  # Use one primary chunker per file type to avoid duplicate fragment streams.
  if lowerExt in MarkdownExts:
    result = chunkMarkdown(content)
    if result.len == 0:
      result = chunkSimple(content)
  elif lowerExt in NimExts:
    result = chunkNim(content)
    if result.len == 0:
      result = chunkSimple(content)
  else:
    result = chunkSimple(content)
  

