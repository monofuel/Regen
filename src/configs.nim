## Configuration management for Regen

import
  std/[strutils, strformat, os, random],
  jsony,
  ./types, ./logs

const
  ConfigVersion* = "0.1.0"

proc generateApiKey*(): string =
  ## Generate a random API key for Bearer authentication.
  randomize()
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  result = ""
  for i in 0..63:  # 64 character key
    result.add(chars[rand(chars.len - 1)])

proc getConfigPath*(): string =
  ## Get the path to the regen config file.
  let configDir = getHomeDir() / ".regen"
  if not dirExists(configDir):
    createDir(configDir)
  result = configDir / "config.json"

proc saveConfig*(config: RegenConfig) =
  ## Save configuration to ~/.regen/config.json.
  let configPath = getConfigPath()
  try:
    let configData = toJson(config)
    writeFile(configPath, configData)
    info &"Config saved to {configPath}"
  except:
    error &"Error saving config to {configPath}: {getCurrentExceptionMsg()}"

proc loadConfig*(): RegenConfig =
  ## Load configuration from ~/.regen/config.json.
  let configPath = getConfigPath()
  
  if not fileExists(configPath):
    # Return default config if file doesn't exist
    info "Config file does not exist, creating new one"
    result = RegenConfig(
      version: ConfigVersion,
      folders: @[],
      gitRepos: @[],
      extensions: @[".nim", ".md", ".txt", ".py", ".js", ".ts", ".rs", ".go"],
      embeddingModel: DefaultEmbeddingModel,
      apiBaseUrl: DefaultApiBaseUrl,
      apiKey: generateApiKey()
    )
    info "Generated new config"
    saveConfig(result)
    return
  
  try:
    let configData = readFile(configPath)
    result = fromJson(configData, RegenConfig)
    
    # Handle backward compatibility - generate API key if missing
    if result.apiKey.len == 0:
      result.apiKey = generateApiKey()
      info "Generated API key for existing config"
      # Save the updated config with the new API key
      saveConfig(result)
    # Backfill apiBaseUrl if missing in existing configs
    if result.apiBaseUrl.len == 0:
      result.apiBaseUrl = DefaultApiBaseUrl
      info "Set default API base URL for existing config"
      saveConfig(result)
    # Backfill embeddingModel if missing
    if result.embeddingModel.len == 0:
      result.embeddingModel = DefaultEmbeddingModel
      info "Set default embedding model for existing config"
      saveConfig(result)
  except:
    error &"Error loading config from {configPath}: {getCurrentExceptionMsg()}"
    # Return default config on error
    result = RegenConfig(
      version: ConfigVersion,
      folders: @[],
      gitRepos: @[],
      extensions: @[".nim", ".md", ".txt", ".py", ".js", ".ts", ".rs", ".go"],
      embeddingModel: DefaultEmbeddingModel,
      apiBaseUrl: DefaultApiBaseUrl,
      apiKey: generateApiKey()
    )

proc addFolderToConfig*(folderPath: string) =
  ## Add a folder path to the config.
  var config = loadConfig()
  
  if not dirExists(folderPath):
    error &"Directory does not exist: {folderPath}"
    return
  
  let absPath = expandFilename(folderPath)
  
  if absPath notin config.folders:
    config.folders.add(absPath)
    saveConfig(config)
    info &"Added folder to config: {absPath}"
  else:
    info &"Folder already in config: {absPath}"

proc addGitRepoToConfig*(repoPath: string) =
  ## Add a git repository path to the config.
  var config = loadConfig()
  
  if not dirExists(repoPath):
    error &"Directory does not exist: {repoPath}"
    return
  
  let absPath = expandFilename(repoPath)
  
  if not dirExists(absPath / ".git"):
    error &"{absPath} is not a git repository"
    return
  
  if absPath notin config.gitRepos:
    config.gitRepos.add(absPath)
    saveConfig(config)
    info &"Added git repo to config: {absPath}"
  else:
    info &"Git repo already in config: {absPath}"

proc findAllIndexes*(): seq[string] =
  ## Find all available index files from configured folders and repos.
  result = @[]
  
  let regenDir = getHomeDir() / ".regen"
  
  # Find folder indexes
  let foldersDir = regenDir / "folders"
  if dirExists(foldersDir):
    for file in walkDir(foldersDir):
      if file.kind == pcFile and file.path.endsWith(".flat"):
        result.add(file.path)
  
  # Find repo indexes
  let reposDir = regenDir / "repos"
  if dirExists(reposDir):
    for file in walkDir(reposDir):
      if file.kind == pcFile and file.path.endsWith(".flat"):
        result.add(file.path)
  
  if result.len == 0:
    warn "No indexes found. Run 'regen --index-all' first to create indexes."

proc showConfig*() =
  ## Display the current configuration.
  let config = loadConfig()
  info "Regen Configuration:"
  info &"  Version: {config.version}"
  info &"  Embedding Model: {config.embeddingModel}"
  info &"  API Base URL: {config.apiBaseUrl}"
  info &"  API Key: {config.apiKey[0..7]}...{config.apiKey[^8..^1]} (Bearer token for API)"
  info &"  Extensions: {config.extensions.join(\", \")}"
  info &"  Folders ({config.folders.len}):"
  for folder in config.folders:
    info &"    - {folder}"
  info &"  Git Repos ({config.gitRepos.len}):"
  for repo in config.gitRepos:
    info &"    - {repo}" 
