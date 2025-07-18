import flatty

# flatty is used to serialize/deserialize to flat files

# top level organization is a git repo, eg monofuel/fragg or monolab/racha
# each repo has many files
# each file has many fragments
# each fragment has a line start, end, and an embedding vector

# nomic-embed-text is used for similarity search with local embeddings and ollama.

# the index flatfiles will be saved at ~/.fraggy/{git_owner}/{git_repo}/{embedding_model_name}.flat
# multiple embedding models may be used for a single repo, and kept in separate files.