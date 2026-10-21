# orca-unraid

Headless [Orca](https://github.com/stablyai/orca) server image for always-on Linux hosts, built for
Unraid. It installs the latest Orca Linux release, Pi, and the Docker CLI.

```text
ghcr.io/iilaurens/orca-unraid:latest
```

## Unraid install

Add this repository under **Docker → Template repositories**:

```text
https://github.com/iiLaurens/orca-unraid
```

Then add the **Orca** container from the templates list. Or copy `orca-unraid.xml` into
`/boot/config/plugins/dockerMan/templates-user/my-Orca.xml`.

The image is pulled from GHCR; nothing is built on the Unraid server.

## What runs

- `orca-ide serve` (orcad), with the browser web client on port `6768`
- Pi (`@earendil-works/pi-coding-agent`), globally installed
- Docker CLI, using Docker's default `/var/run/docker.sock`
- `git`, `gh`, Node 24, Python 3, build tools, `ripgrep`

## Experimental Cloud VM skill

The **Settings → Experimental → Cloud VM** pane expects the official `orca-per-workspace-env` skill.
Its Install button opens an interactive skills-CLI prompt, which a headless container cannot answer.
The image seeds the skill at build time, and the entrypoint copies it into
`/config/.agents/skills` on first start if it is missing.

To refresh it manually:

```bash
docker exec -u orca Orca orca-ide skills install --skill orca-per-workspace-env
```

## Persistence

The image expects these mounts:

```text
/mnt/user/appdata/orca/config   → /config
/mnt/user/appdata/orca/pi       → /config/.pi
/mnt/user/appdata/orca/skills   → /config/.agents/skills
/mnt/user/development          → /mnt/user/development
/var/run/docker.sock           → /var/run/docker.sock:ro
```

`/config/.pi` keeps durable Pi state only: `auth.json`, `settings.json`, `pi-llama-swap.json`,
`trust.json`, the model cache, and installed extensions. Chat sessions are written to
`/tmp/pi-sessions` in the container layer (`PI_CODING_AGENT_SESSION_DIR`), so they die with the
container. There are no anonymous volumes or tmpfs mounts.

`/config` is Orca's profile, credentials, SSH keys, and downloaded runtime slots. `/config/.agents/skills`
is the shared agent-skill root; this setup also mounts the adapted `orca-setup` skill and
`orca-vm` scripts there.

## Docker and dind

The image does not set `DOCKER_HOST`; it uses `/var/run/docker.sock`. Mount a normal host socket
there, or mount a dind socket directory's `docker.sock` file there read-only. The template mounts
the tower's `dind` socket file:

```text
/mnt/user/system/dind/etc/docker.sock → /var/run/docker.sock:ro
```

Read-only prevents deleting or `chmod`-ing the socket. It does not restrict the Docker API.
Only the project tree is mounted into Orca. dind keeps the tower's full `/mnt` mount, so workspace
bind mounts under `/mnt/user/...` (for example the recipe's `/mnt/user/development` and
`/mnt/user/AI` mounts) resolve through dind without giving Orca access to the rest of the array.

## Updates

The workflow builds on every push to `main` and daily at 03:17 UTC, so `:latest` follows Orca and Pi
releases. Manual runs accept `orca_version` and `pi_version` inputs (for example `1.4.237` and
`1.3.0`, or `latest`).

In Unraid, **Force Update** pulls the new `:latest`.

## Build locally

```bash
./build-image.sh
# or pin versions:
ORCA_VERSION=1.4.237 PI_VERSION=1.3.0 ./build-image.sh
```

## Notes

- The GHCR package must be public for Unraid to pull it without credentials.
- Pair the web client once by pasting the `Pairing URL` from the container log. The browser then
  remembers the pairing. See the Orca docs for remote servers.
- The container runs `orca` as Unraid's `nobody`/`users` (99/100) by default. `PUID`, `PGID`, and
  `DOCKER_GID` are configurable in the template.
