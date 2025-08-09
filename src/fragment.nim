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

  result = @[]

  # Always use simple chunking for everything.
  result.add(chunkSimple(content))

  # file format specific chunking.
  if lowerExt in MarkdownExts:
    result.add(chunkMarkdown(content))
  elif lowerExt in NimExts:
    result.add(chunkNim(content))
  


