FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl — keep version in sync with kubernetes_version in ansible/inventory/group_vars/all.yml
RUN curl -fsSL "https://dl.k8s.io/release/v1.33.0/bin/linux/amd64/kubectl" \
    -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl
