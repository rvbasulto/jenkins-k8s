rvbasulto@RG-server:~/projects/jenkins$ cat Dockerfile 
# Jenkins LTS with JDK 17 for the master process
FROM jenkins/jenkins:lts-jdk17

# Switch to root for package installation and system changes
USER root

# -----------------------------
# Base packages for JDK download/extract and apt over HTTPS
# -----------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    tar \
    gzip \
    gnupg \
 && rm -rf /var/lib/apt/lists/*

# -----------------------------
# Install multiple JDKs (11, 17, 21) under /opt/jdks with stable symlinks
# -----------------------------
# Notes:
# - We fetch stable binaries from Adoptium API.
# - We create deterministic symlinks: /opt/jdks/jdk-11, /opt/jdks/jdk-17, /opt/jdks/jdk-21
ENV JDK_BASE=/opt/jdks
RUN set -eux; \
    mkdir -p "$JDK_BASE"; \
    # Download GA releases for JDK 11/17/21 (Linux x64, HotSpot)
    for v in 11 17 21; do \
      curl -fL -o /tmp/jdk${v}.tgz "https://api.adoptium.net/v3/binary/latest/${v}/ga/linux/x64/jdk/hotspot/normal/eclipse?project=jdk"; \
      tar -xzf /tmp/jdk${v}.tgz -C "$JDK_BASE"; \
      rm -f /tmp/jdk${v}.tgz; \
    done; \
    ln -s $(ls -d $JDK_BASE/jdk-11*) $JDK_BASE/jdk-11; \
    ln -s $(ls -d $JDK_BASE/jdk-17*) $JDK_BASE/jdk-17; \
    ln -s $(ls -d $JDK_BASE/jdk-21*) $JDK_BASE/jdk-21

# Helpful env vars for Jenkins tool config (optional)
ENV JDK11=$JDK_BASE/jdk-11
ENV JDK17=$JDK_BASE/jdk-17
ENV JDK21=$JDK_BASE/jdk-21

# -----------------------------
# Docker CLI & Docker Compose v2
# -----------------------------
# Notes:
# - Installs docker-ce-cli and docker-compose-plugin from Docker's official APT repo.
# - This container is intended to talk to a Docker daemon via /var/run/docker.sock
#   mounted from the Kubernetes node, or via a DinD sidecar.
ENV DEBIAN_FRONTEND=noninteractive
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && . /etc/os-release \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce-cli \
      docker-compose-plugin \
      docker-buildx-plugin \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Allow 'jenkins' user to run Docker CLI commands
RUN groupadd -f docker && usermod -aG docker jenkins

# Optional: enable BuildKit for faster and more capable builds
ENV DOCKER_BUILDKIT=1 \
    COMPOSE_DOCKER_CLI_BUILD=1

# -----------------------------
# Install kubectl
# -----------------------------
RUN curl -LO "https://dl.k8s.io/release/v1.30.1/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Back to Jenkins user (the base image already uses JDK 17 for the master)
USER jenkins