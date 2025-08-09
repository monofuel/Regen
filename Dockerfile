FROM nimlang/nim:2.2.2-regular

# Minimal packages needed for build/runtime
RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libpcre3-dev \
    ripgrep \
    curl \
    wget \
    dnsutils \
    ca-certificates && \
  update-ca-certificates && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install nimble deps first for better layer caching
ADD regen.nimble /app/
RUN mkdir -p src && nimble install -y -d

# Add sources and build
ADD src/ /app/src
RUN mkdir -p bin && nim c -d:release --out:bin/regen src/regen.nim

# Default working dir and command
WORKDIR /app/bin
CMD ["./regen"]


