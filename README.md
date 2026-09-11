# docker-pi

Run the latest [pi](https://pi.dev) coding agent inside a container. The
container bind-mounts the host root filesystem at `/host` so pi can work
anywhere on the machine, and mounts your `~/.pi/agent` directory so settings,
credentials, and sessions persist on the host.

This project builds architecture-specific images for:

- `linux/amd64` — desktops, servers, VMs
- `linux/arm64/v8` — Raspberry Pi 4/5, Raspberry Pi 3B with a 64-bit OS,
  Apple Silicon, Nvidia Spark DGX, ARM servers

The wrapper script is runtime-agnostic: it uses Docker if available,
otherwise Podman, and it auto-selects the correct architecture-specific image.

## What this gives you

- **Latest pi from pi.dev** installed via `npm` inside the image.
- **Node 24 inside the image** so Node/npm do not pollute the host.
- **No overwrite of existing pi**: the wrapper is named `pi-in-docker` and is
  installed to `~/bin` by default.
- **Portable config**: your `~/.pi/agent` settings are mounted into the
  container at runtime, not baked into the image.
- **Full host access**: the host `/` is bind-mounted as `/host`, with the
  current working directory preserved.
- **Container runtime flexibility**: Docker or Podman.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile` | Builds the container image with Node 24, pi, and `jq`. |
| `Makefile` | Builds and exports `amd64` and `arm64` images. |
| `pi-in-docker` | Wrapper that runs pi in a container with proper mounts and UID mapping. |
| `ship-pi-in-docker.sh` | SSH-based staging/install script for a remote host. |
| `ansible/` | Ansible playbook and role for remote install. |
| `README.md` | This file. |

## Quick start (local)

```bash
cd /path/to/docker-pi

# Build for the current machine
make build

# Or explicitly:
make build-amd64
make build-arm64

# Run pi in the current directory
./pi-in-docker

# Or pass arguments
./pi-in-docker -p "Summarize this repo"
```

Your local `~/.pi/agent` is mounted automatically, so settings, sessions, and
`/login` credentials are reused.

## Build and export a tarball

```bash
# Current host architecture
make export

# Specific architectures
make export-amd64
make export-arm64

# Both
make export-all
```

Tarballs are written to `dist/`:

```text
dist/pi-in-docker-latest-amd64.tar.gz
dist/pi-in-docker-latest-arm64.tar.gz
```

## Deploy to a remote host

```bash
./ship-pi-in-docker.sh wright@ercam
./ship-pi-in-docker.sh -a arm64 pi@raspberrypi.local
./ship-pi-in-docker.sh -a amd64 --install-podman admin@newserver
```

The script will:

1. Build the requested architecture image if it is not already present.
2. Export it to a tarball.
3. Copy the tarball and `pi-in-docker` wrapper to the target host.
4. Detect Docker or Podman on the target; if neither is found, install Podman.
5. Add the remote user to the `docker` group when Docker is used.
6. Load the image into the selected runtime.
7. Install the wrapper to `~/bin` (or `/usr/local/bin` with `--system-bin`).

If you only want to stage files without installing, use `--no-install`.

## Deploy with Ansible

Build the images first:

```bash
make export-all
```

Copy `ansible/inventory.example.yml` to `ansible/inventory.yml`, edit it for
your hosts, then run:

```bash
cd ansible
ansible-playbook -i inventory.yml install.yml
```

The playbook installs the wrapper to `~/bin` and loads the correct image
for each target's architecture.

## Copy pi config and credentials to a remote host

This repo ships the runtime image only. Keep config and credentials separate.

### Copy tracked config

From your local `~/.pi` git repo:

```bash
cd ~/.pi
git ls-files | tar -czf - -T - | \
  ssh wright@target "mkdir -p ~/.pi && cd ~/.pi && tar -xzf -"
```

### Copy credentials

Your pi credentials live in the untracked file `~/.pi/agent/auth.json`.

```bash
ssh -t wright@target "mkdir -p ~/.pi/agent && chmod 700 ~/.pi/agent"
scp ~/.pi/agent/auth.json wright@target:~/.pi/agent/auth.json
ssh -t wright@target "chmod 600 ~/.pi/agent/auth.json"
```

### Re-authenticate instead of copying

If you prefer not to move tokens across machines, log in fresh on the target:

```bash
pi-in-docker
/login github-copilot
/login google
/login kimi.ai
/login spark
```

## First run on a remote host

```bash
ssh -t wright@target
pi-in-docker --version
pi-in-docker -p "hello from $(hostname)"
```

If your settings use `externalEditor: "code --wait"` and a GUI editor is not
installed, change it in `~/.pi/agent/settings.json` on the target to `vi`,
`vim`, or `nano`.

## Web search with SearXNG

The image includes `jq`. If you have copied your
[SearXNG search skill](https://github.com/lidar532/pi-config) to the target,
`/web` queries will work inside the container as long as the container can
reach your SearXNG instance. If LAN hostnames like `spark:12001` do not
resolve from inside the container, run with:

```bash
PI_NETWORK=host pi-in-docker
```

or add the host manually with `--add-host` (pass it before any pi args).

## Updating to the latest pi

Because the image installs `@earendil-works/pi-coding-agent` without pinning,
each rebuild fetches the latest release from pi.dev:

```bash
cd /path/to/docker-pi
make export-all
./ship-pi-in-docker.sh wright@target
```

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `PI_IMAGE` | `docker.io/lidar532/pi-in-docker:latest-<arch>` | Full image reference. |
| `PI_ARCH` | auto from `uname -m` | Architecture tag suffix (`amd64` or `arm64`). |
| `PI_RUNTIME` | auto (`docker` preferred) | Container runtime to use. |
| `PI_NETWORK` | `bridge` | Container network mode. Use `host` for LAN hostnames. |
| `PI_BIN` | `~/bin` | Expected install directory (informational). |

Example:

```bash
PI_NETWORK=host PI_RUNTIME=podman ./pi-in-docker
```

## Notes

- The image creates a fallback `piuser` with UID/GID 1000. The runtime wrapper
  overrides this with the actual host UID/GID so file ownership matches.
- The container is stateless except for the bind mounts. Sessions and settings
  live on the host in `~/.pi/agent`.
- Node.js and npm live only inside the image; you do not need them on the host.
- Raspberry Pi 3B must be running a **64-bit OS** to use the `arm64` image.

## License

MIT
