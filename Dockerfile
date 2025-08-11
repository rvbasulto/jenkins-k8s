# Dockerfile
FROM jenkins/jenkins:lts-jdk17

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates tar gzip \
 && rm -rf /var/lib/apt/lists/*

ENV JDK_BASE=/opt/jdks
RUN set -eux; \
    mkdir -p "$JDK_BASE"; \
    # Descargas estables desde el API de Adoptium (siempre redirigen al binario correcto)
    for v in 11 17 21; do \
      curl -fL -o /tmp/jdk${v}.tgz "https://api.adoptium.net/v3/binary/latest/${v}/ga/linux/x64/jdk/hotspot/normal/eclipse?project=jdk"; \
      tar -xzf /tmp/jdk${v}.tgz -C "$JDK_BASE"; \
      rm -f /tmp/jdk${v}.tgz; \
    done; \
    ln -s $(ls -d $JDK_BASE/jdk-11*) $JDK_BASE/jdk-11; \
    ln -s $(ls -d $JDK_BASE/jdk-17*) $JDK_BASE/jdk-17; \
    ln -s $(ls -d $JDK_BASE/jdk-21*) $JDK_BASE/jdk-21

ENV JDK11=$JDK_BASE/jdk-11
ENV JDK17=$JDK_BASE/jdk-17
ENV JDK21=$JDK_BASE/jdk-21
# Java 17 ya es el default de la imagen base
USER jenkins