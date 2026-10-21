# syntax=docker/dockerfile:1.7
# Orca headless server for an always-on Linux host.
#
# The image runs `orca-ide serve` (orcad), not the Electron window. It installs Orca from the
# published Linux .deb so the CLI, orcad template, and web client are all present and versioned
# together. Docker is the CLI only and uses Docker's default /var/run/docker.sock; mount a host
# socket or a dind socket file there.

ARG NODE_IMAGE=node:24-bookworm-slim
FROM ${NODE_IMAGE} AS node-runtime

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
# Track the latest releases by default; override either to pin a version.
ARG ORCA_VERSION=latest
ARG PI_VERSION=latest
# build-image.sh changes this when either version is "latest", so those layers actually refresh.
ARG BUILD_REFRESH=0

# orcad is the headless server. Electron serve would need an X server and is much heavier.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/config \
    XDG_CONFIG_HOME=/config/.config \
    XDG_CACHE_HOME=/config/.cache \
    XDG_DATA_HOME=/config/.local/share \
    ORCA_USER_DATA_PATH=/config/profile \
    ORCA_USER_DATA=/config/profile \
    ORCA_SERVE_RUNTIME=orcad \
    DOCKER_CONFIG=/config/.docker

# Electron/Chromium runtime libraries, shell tooling, and the compilers agent CLIs expect.
# The Orca .deb declares the Electron, computer-use, and Xvfb packages it needs, but installing
# them here keeps the later apt transaction predictable and lets Docker CLI installation share it.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      curl \
      dbus-x11 \
      git \
      jq \
      less \
      libasound2t64 \
      libatk-bridge2.0-0 \
      libatspi2.0-0 \
      libdrm2 \
      libgbm1 \
      libgtk-3-0 \
      libnotify4 \
      libnss3 \
      libsecret-1-0 \
      libuuid1 \
      libxcomposite1 \
      libxdamage1 \
      libxfixes3 \
      libxkbcommon0 \
      libxrandr2 \
      libxss1 \
      libxtst6 \
      openssh-client \
      procps \
      psmisc \
      python3 \
      python3-venv \
      ripgrep \
      rsync \
      tar \
      unzip \
      util-linux \
      xdg-utils \
      xz-utils \
      zip; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
      "$(dpkg --print-architecture)" "$(. /etc/os-release && echo "$VERSION_CODENAME")" \
      > /etc/apt/sources.list.d/docker.list; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
      "$(dpkg --print-architecture)" > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      docker-buildx-plugin \
      docker-ce-cli \
      docker-compose-plugin \
      gh; \
    rm -rf /var/lib/apt/lists/*

# Node for the project and agent CLIs, copied from the official image rather than re-keying a repo.
COPY --from=node-runtime /usr/local/bin/node /usr/local/bin/node
COPY --from=node-runtime /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && ln -sf ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
 && node --version

# The published Linux package installs /usr/bin/orca-ide, the orcad template, and the web client.
RUN set -eux; \
    echo "build refresh: ${BUILD_REFRESH}"; \
    if [ "$ORCA_VERSION" = "latest" ]; then \
      tag="$(curl -fsSL https://api.github.com/repos/stablyai/orca/releases/latest | jq -r '.tag_name')"; \
    else \
      tag="v${ORCA_VERSION#v}"; \
    fi; \
    version="${tag#v}"; \
    case "$(dpkg --print-architecture)" in \
      amd64) deb_arch=amd64 ;; \
      arm64) deb_arch=arm64 ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    deb="orca-ide_${version}_${deb_arch}.deb"; \
    curl -fsSL -o /tmp/orca.deb \
      "https://github.com/stablyai/orca/releases/download/${tag}/${deb}"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/orca.deb; \
    rm -f /tmp/orca.deb; \
    rm -rf /var/lib/apt/lists/*; \
    template="$(find /opt -maxdepth 5 -path '*/orcad-template/orcad-template.json' -print -quit)"; \
    test -n "$template"; \
    orca-ide --version

# The runtime user defaults to Unraid's nobody/users (99/100). The entrypoint can remap it.
RUN groupadd -o --gid 100 orca \
 && useradd -o --uid 99 --gid orca --home-dir /config --shell /bin/bash --no-create-home orca \
 && mkdir -p /config \
 && chown orca:orca /config

# Pi is the agent CLI; installing it globally keeps every Orca terminal ready to run `pi`.
RUN set -eux; \
    echo "build refresh: ${BUILD_REFRESH}"; \
    HOME=/root npm_config_cache=/tmp/npm-cache npm install -g --no-fund --no-audit \
      "@earendil-works/pi-coding-agent@${PI_VERSION}"; \
    HOME=/root pi --version; \
    rm -rf /tmp/npm-cache

# Global npm installs by the runtime user must not target root-owned /usr/local. This keeps
# `npm install -g <agent>` working as orca and persists the result in the /config mount.
ENV NPM_CONFIG_PREFIX=/config/.npm-global \
    PATH=$PATH:/config/.npm-global/bin

COPY entrypoint.sh /usr/local/bin/orca-entrypoint
RUN chmod 0755 /usr/local/bin/orca-entrypoint

WORKDIR /config
EXPOSE 6768
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${ORCA_PORT:-6768}/web-index.html" >/dev/null || exit 1
ENTRYPOINT ["/usr/local/bin/orca-entrypoint"]
CMD ["serve"]
