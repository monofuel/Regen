## Search functionality for Regen - ripgrep and embedding search

import
  std/[strutils, os, osproc, json, algorithm, math, tables],
  openai_leap,
  ./types, ./configs

const
  SimilarityEmbeddingModel* = "nomic-embed-text"
  #SimilarityEmbeddingModel* = "Qwen/Qwen3-Embedding-0.6B-GGUF"
  MaxInFlight* = 10

var localOllamaApi*: OpenAiApi

proc initEmbeddingClient*() =
  ## Initialize the OpenAI-compatible client using values from config.
  let cfg = loadConfig()
  localOllamaApi = newOpenAiApi(
    baseUrl = cfg.apiBaseUrl,
    apiKey = cfg.apiKey,
    maxInFlight = MaxInFlight
  )

proc generateEmbedding*(text: string, model: string = SimilarityEmbeddingModel): seq[float32] =
  ## Generate an embedding for the given text using ollama.
  if localOllamaApi.isNil:
    initEmbeddingClient()
  let embedding = localOllamaApi.generateEmbeddings(
    model = model,
    input = text
  )
  result = embedding.data[0].embedding

proc cosineSimilarity*(a, b: seq[float32]): float32 =
  ## Calculate cosine similarity between two embedding vectors.
  if a.len != b.len:
    raise newException(ValueError, "Vectors must have the same length")
  
  var dotProduct = 0.0'f32
  var normA = 0.0'f32
  var normB = 0.0'f32
  
  for i in 0..<a.len:
    dotProduct += a[i] * b[i]
    normA += a[i] * a[i]
    normB += b[i] * b[i]
  
  let magnitude = sqrt(normA) * sqrt(normB)
  if magnitude == 0.0'f32:
    return 0.0'f32
  
  result = dotProduct / magnitude

proc extAllowed(filePath: string, allowed: seq[string]): bool =
  ## Check if the file extension is allowed by the provided list (empty list means allow all).
  if allowed.len == 0:
    return true
  let ext = splitFile(filePath).ext.toLower
  for a in allowed:
    if ext == a:
      return true
  false

proc findSimilarFragments*(index: RegenIndex, queryText: string, maxResults: int = 10, model: string = SimilarityEmbeddingModel, allowedExtensions: seq[string] = @[]): seq[SimilarityResult] =
  ## Find the most similar fragments to the query text.
  ## If allowedExtensions is non-empty, restrict results to files whose extension is in the list.
  let queryEmbedding = generateEmbedding(queryText, model)
  var results: seq[SimilarityResult] = @[]
  
  # Collect all fragments with their similarity scores
  case index.kind
  of regen_git_repo:
    for _, file in index.repo.files.pairs:
      if not extAllowed(file.path, allowedExtensions):
        continue
      for fragment in file.fragments:
        if fragment.model == model:
          let similarity = cosineSimilarity(queryEmbedding, fragment.embedding)
          results.add(SimilarityResult(
            fragment: fragment,
            file: file,
            similarity: similarity
          ))
  of regen_folder:
    for _, file in index.folder.files.pairs:
      if not extAllowed(file.path, allowedExtensions):
        continue
      for fragment in file.fragments:
        if fragment.model == model:
          let similarity = cosineSimilarity(queryEmbedding, fragment.embedding)
          results.add(SimilarityResult(
            fragment: fragment,
            file: file,
            similarity: similarity
          ))
  
  # Sort by similarity (highest first) and return top results
  results.sort(proc(a, b: SimilarityResult): int =
    if a.similarity > b.similarity: -1
    elif a.similarity < b.similarity: 1
    else: 0
  )
  
  if results.len > maxResults:
    result = results[0..<maxResults]
  else:
    result = results

proc ripgrepSearch*(index: RegenIndex, pattern: string, caseSensitive: bool = true, maxResults: int = 100): seq[RipgrepResult] =
  ## Search through all files in the index using actual ripgrep (rg) command.
  ## Returns matching lines with file info and line numbers.
  var results: seq[RipgrepResult] = @[]
  
  # Get the search directory based on index type
  let searchPath = case index.kind
    of regen_git_repo:
      index.repo.path
    of regen_folder:
      index.folder.path
  
  # Build ripgrep command (don't limit per file, we'll limit total results)
  var cmd = "rg --json --line-number --column"
  if not caseSensitive:
    cmd.add(" --ignore-case")
  
  # Add the pattern and search path
  cmd.add(" " & pattern.quoteShell() & " " & searchPath.quoteShell())
  
  try:
    let (output, exitCode) = execCmdEx(cmd)
    
    # If rg returns non-zero (no matches or error), return empty results
    if exitCode != 0:
      return @[]
    
    # Parse JSON output from ripgrep
    for line in output.strip().split('\n'):
      if line.strip().len == 0:
        continue
        
      # Stop if we've reached max results
      if results.len >= maxResults:
        break
        
      try:
        let jsonData = parseJson(line)
        
        # Only process "match" type entries
        if jsonData.hasKey("type") and jsonData["type"].getStr() == "match":
          let data = jsonData["data"]
          let filePath = data["path"]["text"].getStr()
          let lineNum = data["line_number"].getInt()
          let lineText = data["lines"]["text"].getStr().strip()  # Strip newlines
          let submatches = data["submatches"]
          
          # Find the corresponding RegenFile
          var regenFile: RegenFile
          var fileFound = false
          
          case index.kind
          of regen_git_repo:
            if index.repo.files.hasKey(filePath):
              regenFile = index.repo.files[filePath]
              fileFound = true
            else:
              for _, file in index.repo.files.pairs:
                if file.path == filePath or file.path.endsWith(filePath):
                  regenFile = file
                  fileFound = true
                  break
          of regen_folder:
            if index.folder.files.hasKey(filePath):
              regenFile = index.folder.files[filePath]
              fileFound = true
            else:
              for _, file in index.folder.files.pairs:
                if file.path == filePath or file.path.endsWith(filePath):
                  regenFile = file
                  fileFound = true
                  break
          
          # If we found the file in our index, create a result for each submatch
          if fileFound:
            for submatch in submatches:
              if results.len >= maxResults:
                break
              results.add(RipgrepResult(
                file: regenFile,
                lineNumber: lineNum,
                lineContent: lineText,
                matchStart: submatch["start"].getInt(),
                matchEnd: submatch["end"].getInt() - 1  # ripgrep uses exclusive end
              ))
            
      except JsonParsingError, KeyError:
        # Skip malformed JSON lines
        continue
        
  except OSError:
    # ripgrep command failed, return empty results
    return @[]
  
  result = results

proc ripgrepSearchInFile*(filePath: string, pattern: string, caseSensitive: bool = true): seq[tuple[lineNumber: int, lineContent: string, matchStart: int, matchEnd: int]] =
  ## Search for pattern in a single file using actual ripgrep.
  var results: seq[tuple[lineNumber: int, lineContent: string, matchStart: int, matchEnd: int]] = @[]
  
  if not fileExists(filePath):
    return @[]
  
  # Build ripgrep command for single file
  var cmd = "rg --json --line-number --column"
  if not caseSensitive:
    cmd.add(" --ignore-case")
  
  cmd.add(" " & pattern.quoteShell() & " " & filePath.quoteShell())
  
  try:
    let (output, exitCode) = execCmdEx(cmd)
    
    # If rg returns non-zero (no matches or error), return empty results
    if exitCode != 0:
      return @[]
    
    # Parse JSON output from ripgrep
    for line in output.strip().split('\n'):
      if line.strip().len == 0:
        continue
        
      try:
        let jsonData = parseJson(line)
        
        # Only process "match" type entries
        if jsonData.hasKey("type") and jsonData["type"].getStr() == "match":
          let data = jsonData["data"]
          let lineNum = data["line_number"].getInt()
          let lineText = data["lines"]["text"].getStr().strip()  # Strip newlines
          let submatches = data["submatches"]
          
          # Add a result for each submatch
          for submatch in submatches:
            results.add((
              lineNumber: lineNum,
              lineContent: lineText,
              matchStart: submatch["start"].getInt(),
              matchEnd: submatch["end"].getInt() - 1  # ripgrep uses exclusive end
            ))
            
      except JsonParsingError, KeyError:
        # Skip malformed JSON lines
        continue
        
  except OSError:
    # ripgrep command failed
    return @[]
  
  result = results 
