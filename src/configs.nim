## Configuration management for Fraggy

import
  std/[strutils, strformat, os],
  jsony,
  ./types, ./search, ./logs

const
  ConfigVersion* = "0.1.0"

proc getConfigPath*(): string =
  ## Get the path to the fraggy config file.
  let configDir = getHomeDir() / ".fraggy"
  if not dirExists(configDir):
    createDir(configDir)
  result = configDir / "config.json"

proc loadConfig*(): FraggyConfig =
  ## Load configuration from ~/.fraggy/config.json.
  let configPath = getConfigPath()
  
  if not fileExists(configPath):
    # Return default config if file doesn't exist
    result = FraggyConfig(
      version: ConfigVersion,
      folders: @[],
      gitRepos: @[],
      extensions: @[".nim", ".md", ".txt", ".py", ".js", ".ts", ".rs", ".go"],
      embeddingModel: SimilarityEmbeddingModel
    )
    return
  
  try:
    let configData = readFile(configPath)
    result = fromJson(configData, FraggyConfig)
  except:
    error &"Error loading config from {configPath}: {getCurrentExceptionMsg()}"
    # Return default config on error
    result = FraggyConfig(
      version: ConfigVersion,
      folders: @[],
      gitRepos: @[],
      extensions: @[".nim", ".md", ".txt", ".py", ".js", ".ts", ".rs", ".go"],
      embeddingModel: SimilarityEmbeddingModel
    )

proc saveConfig*(config: FraggyConfig) =
  ## Save configuration to ~/.fraggy/config.json.
  let configPath = getConfigPath()
  try:
    let configData = toJson(config)
    writeFile(configPath, configData)
    info &"Config saved to {configPath}"
  except:
    error &"Error saving config to {configPath}: {getCurrentExceptionMsg()}"

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

proc showConfig*() =
  ## Display the current configuration.
  let config = loadConfig()
  info "Fraggy Configuration:"
  info &"  Version: {config.version}"
  info &"  Embedding Model: {config.embeddingModel}"
  info &"  Extensions: {config.extensions.join(\", \")}"
  info &"  Folders ({config.folders.len}):"
  for folder in config.folders:
    info &"    - {folder}"
  info &"  Git Repos ({config.gitRepos.len}):"
  for repo in config.gitRepos:
    info &"    - {repo}" 