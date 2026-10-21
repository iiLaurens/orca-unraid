#!/usr/bin/env bash
# Starts the Orca headless server as an unprivileged user, with Docker access and appdata
# remapped on first boot. Unraid templates pass host ownership as PUID/PGID and the Docker socket
# group as DOCKER_GID; everything else is a normal container env var.
set -euo pipefail

log() { printf '[orca] %s\n' "$*" >&2; }

PUID=${PUID:-99}
PGID=${PGID:-100}
DOCKER_GID=${DOCKER_GID:-100}
UMASK=${UMASK:-022}
umask "$UMASK"

if [ "$(id -u)" -eq 0 ]; then
  if getent group orca >/dev/null; then
    groupmod -o -g "$PGID" orca
  else
    groupadd -o -g "$PGID" orca
  fi
  if [ "$(id -u orca)" != "$PUID" ] || [ "$(id -g orca)" != "$PGID" ]; then
    usermod -o -u "$PUID" -g "$PGID" orca
  fi
  log "running as ${PUID}:${PGID}, docker gid ${DOCKER_GID}"
  if getent group docker >/dev/null; then
    groupmod -o -g "$DOCKER_GID" docker
  else
    groupadd -o -g "$DOCKER_GID" docker
  fi
  usermod -aG docker orca

  mkdir -p \
    /config/.cache \
    /config/.config \
    /config/.docker \
    /config/.local/share \
    /config/.npm-global \
    /config/.orca \
    /config/.ssh \
    /config/profile

  # These are created here, so they must be handed to the runtime user even when the recursive
  # ownership marker is already current.
  for dir in \
    /config/.cache \
    /config/.config \
    /config/.docker \
    /config/.local \
    /config/.npm-global \
    /config/.orca \
    /config/.ssh \
    /config/profile; do
    [ -e "$dir" ] && chown "$PUID:$PGID" "$dir"
  done

  owner_marker=/config/.orca-owner
  desired_owner="${PUID}:${PGID}"
  if [ "$(cat "$owner_marker" 2>/dev/null || true)" != "$desired_owner" ]; then
    log "taking ownership of /config for ${desired_owner}"
    chown -R "$PUID:$PGID" /config
    printf '%s\n' "$desired_owner" >"$owner_marker"
    chown "$PUID:$PGID" "$owner_marker"
  fi

  seed_skill=/opt/orca-seed-skills/orca-per-workspace-env
  dest_skill=/config/.agents/skills/orca-per-workspace-env
  if [ -d "$seed_skill" ] && [ ! -e "$dest_skill/SKILL.md" ]; then
    if [ -w /config/.agents/skills ]; then
      cp -R "$seed_skill" /config/.agents/skills/
      chown -R "$PUID:$PGID" "$dest_skill"
      log "seeded the official Cloud VM skill"
    else
      log "skills dir is not writable; install orca-per-workspace-env manually"
    fi
  fi

  exec runuser --user orca --preserve-environment -- "$0" "$@"
fi

if docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
  log "docker: connected ($(docker version --format '{{.Server.Version}}'))"
elif [ -e /var/run/docker.sock ] || [ -n "${DOCKER_HOST:-}" ]; then
  log "docker: socket configured but the daemon is not answering"
else
  log "docker: no socket at /var/run/docker.sock; Docker features will be unavailable"
fi

if [ "${1:-}" = "serve" ]; then
  shift
  serve_args=(serve --port "${ORCA_PORT:-6768}")
  if [ -n "${ORCA_PAIRING_ADDRESS:-}" ]; then
    serve_args+=(--pairing-address "$ORCA_PAIRING_ADDRESS")
  fi
  if [ "${ORCA_NO_PAIRING:-0}" = "1" ]; then
    serve_args+=(--no-pairing)
  fi
  if [ "${ORCA_MOBILE_PAIRING:-0}" = "1" ]; then
    serve_args+=(--mobile-pairing)
  fi
  if [ -n "${ORCA_SERVE_EXTRA_ARGS:-}" ]; then
    read -r -a extra_args <<<"$ORCA_SERVE_EXTRA_ARGS"
    serve_args+=("${extra_args[@]}")
  fi
  serve_args+=("$@")
  log "web client: http://${ORCA_PAIRING_ADDRESS:-<server-address>}:${ORCA_PORT:-6768}/web-index.html"
  log "pairing URL and web client URL are printed below; paste the pairing URL into the web client"
  exec orca-ide "${serve_args[@]}"
fi

exec "$@"
