# docker-pi

Run the latest [pi](https://pi.dev) coding agent inside a Docker container.
The container bind-mounts the host root filesystem at `/host` so pi can work
anywhere on the machine, and mounts your `~/.pi/agent` directory so settings,
credentials, and sessions persist on the host.

This project is designed for use on `ercam` and this development machine, but
it does not touch the host's native pi installation unless you explicitly
install the wrapper.

## What this gives you

- **Latest pi from pi.dev** installed via `npm` inside the image.
- **Node 24 inside the image** so Node/npm do not pollute the host.
- **No overwrite of existing pi**: the wrapper is named `pi.in.docker` and can
  optionally be linked to `pi` later.
- **Portable config**: your `~/.pi/agent` settings are mounted into the container
  at runtime, not baked into the image.
- **Full host access**: the host `/` is bind-mounted as `/host`, with the
  current working directory preserved.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile` | Builds the container image with Node 24 and the latest pi. |
| `pi.in.docker` | Wrapper that runs pi in the container with proper mounts and UID mapping. |
| `ship-pi-to-ercam.sh` | Builds, exports, and stages the image on `ercam`. |
| `README.md` | This file. |

## Quick start (local)

```bash
cd /path/to/docker-pi

# Build the image
docker build -t pi-ercam:latest -f Dockerfile .

# Run pi in the current directory
./pi.in.docker

# Or pass arguments
./pi.in.docker -p "Summarize this repo"
```

Your local `~/.pi/agent` is mounted automatically, so settings, sessions, and
`/login` credentials are reused.

## Deploy to ercam

```bash
cd /path/to/docker-pi
./ship-pi-to-ercam.sh
```

This script:

1. Builds `pi-ercam:latest` locally.
2. Exports it to `pi-ercam.tar.gz`.
3. Copies the tarball and `pi.in.docker` to `wright@ercam:/tmp/docker-pi-ship/`.

It does **not** install anything into `/usr/local/bin`. Complete the install
manually on ercam:

```bash
ssh -t wright@ercam

# 1. Make sure your user can run Docker without sudo.
sudo usermod -aG docker $USER
# Log out and back in, or run:
newgrp docker

# 2. Load the image.
docker load < /tmp/docker-pi-ship/pi-ercam.tar.gz

# 3. (optional) Install the wrapper system-wide.
sudo mv /tmp/docker-pi-ship/pi.in.docker /usr/local/bin/pi.in.docker
sudo chmod 755 /usr/local/bin/pi.in.docker

# 4. Copy your tracked pi config (models/settings) from this machine.
#    Run this from your local ~/.pi repo:
#      git ls-files | tar -czf - -T - | \
#        ssh wright@ercam "mkdir -p ~/.pi && cd ~/.pi && tar -xzf -"

# 5. Copy your credentials (see "Copy credentials to ercam" below).

# 6. Run pi.
pi.in.docker
```

## Copy settings and models to ercam

This repo does **not** copy your `~/.pi/agent` directory; it only ships the
runtime image. Keep config sync separate, for example by copying the tracked
files from your local `~/.pi` git repo:

```bash
cd ~/.pi
git ls-files | tar -czf - -T - | \
  ssh wright@ercam "mkdir -p ~/.pi && cd ~/.pi && tar -xzf -"
```

After that, on ercam, you can run:

```bash
pi.in.docker
```

## Copy credentials and API keys to ercam

Your pi credentials are stored in the untracked file `~/.pi/agent/auth.json`.
The easiest way to move them to ercam is a single secure copy:

```bash
# Make sure the agent directory already exists on ercam
ssh -t wright@ercam "mkdir -p ~/.pi/agent && chmod 700 ~/.pi/agent"

# Copy the credentials file
scp ~/.pi/agent/auth.json wright@ercam:~/.pi/agent/auth.json

# Lock down permissions
ssh -t wright@ercam "chmod 600 ~/.pi/agent/auth.json"
```

### Provider-specific notes

Your local `auth.json` contains entries for these providers:

- `github-copilot`
- `Google.com (Personal)`
- `Google.com (NOAA)`
- `kimi.ai`
- `Xplane-FLA.lan`
- `ollama.com`
- `spark`

For **subscription/OAuth providers** (`github-copilot`, Google), tokens may be
session- or device-bound. If pi refuses to authenticate after copying,
simply run `/login github-copilot` or `/login google` inside pi on ercam and
re-authorize.

For **API-key providers** (`kimi.ai`, `spark`), copying `auth.json` is usually
enough, because the key is stored verbatim. If you prefer environment
variables, set them in `~/.bashrc` on ercam and reference them in
`~/.pi/agent/models.json` with `$VAR_NAME` syntax.

Local/self-hosted providers (`Xplane-FLA.lan`, `ollama.com`) normally use a
dummy key and rely on the endpoint being reachable from ercam.

### Optional: re-authenticate fresh on ercam

If you do not want to copy the file, you can recreate credentials on the new
machine:

```bash
pi.in.docker
/login github-copilot
/login google
/login kimi.ai
/login spark
```

This avoids moving any tokens across machines.

## First run on ercam

After loading the image and copying config + credentials, test it:

```bash
ssh -t wright@ercam
pi.in.docker --version
pi.in.docker -p "hello from ercam"
```

If your settings use `externalEditor: "code --wait"` and a GUI editor is not
installed on ercam, change it in `~/.pi/agent/settings.json` on ercam to an
editor that is available, e.g. `vi`, `vim`, or `nano`. Since ercam is a
headless server, `vi` is the most likely choice.

If your `settings.json` lists installed packages (for example
`npm:@narumitw/pi-btw`), pi will prompt to install them on first startup, or
you can install them manually:

```bash
pi.in.docker
pi install npm:@narumitw/pi-btw
```

## Updating to the latest pi from pi.dev

The pi package is installed globally inside the image at build time. To get the
latest version, just rebuild and re-ship:

```bash
cd /path/to/docker-pi

# Locally
./ship-pi-to-ercam.sh

# On ercam (after the ship script finishes)
ssh -t wright@ercam "docker load < /tmp/docker-pi-ship/pi-ercam.tar.gz"
```

Because the image uses `npm install -g @earendil-works/pi-coding-agent` without
pinning a version, each rebuild fetches the latest release from pi.dev.

## Customization

| Variable | Default | Meaning |
| --- | --- | --- |
| `PI_DOCKER_IMAGE` | `pi-ercam:latest` | Image name used by the wrapper. |
| `PI_HOST_MOUNT` | `/host` | Where the host root is mounted in the container. |
| `PI_CODING_AGENT_DIR` | `$HOME/.pi/agent` | Host pi config directory. |

Example:

```bash
PI_DOCKER_IMAGE=my-pi:latest ./pi.in.docker
```

## Notes

- The image creates a `wright` user with UID/GID 1000 to match `wright@ercam`.
  At runtime the wrapper overrides this with your actual host UID/GID.
- The container is stateless except for the bind mounts. Sessions and settings
  live on the host in `~/.pi/agent`.
- Node.js and npm live only inside the image; you do not need them on the host.

## License

MIT
