#!/usr/bin/env bash
#
# ship-pi-in-docker.sh: build, export, and stage (or install) the pi-in-docker
# image and wrapper on a remote Linux host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REGISTRY="docker.io/lidar532"
DEFAULT_NAME="pi-in-docker"
DEFAULT_VERSION="latest"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

ARCH="auto"
RUNTIME="auto"
INSTALL_DIR="\$HOME/bin"
SYSTEM_BIN=false
NO_INSTALL=false
INSTALL_PODMAN=false
TARGET=""

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

show_help() {
    cat <<'EOF'
Usage: ship-pi-in-docker.sh [options] user@hostname

Build, export, and install the pi-in-docker container image and wrapper on a
remote Linux host. The wrapper runs the pi coding agent inside Docker or
Podman and selects the correct architecture-specific image automatically.

Options:
  -a, --arch amd64|arm64|auto   Target architecture (default: auto-detect from
                                 'uname -m' on the remote host).
                                 amd64  = most desktops/servers/VMs
                                 arm64  = Raspberry Pi 4/5, Pi 3B 64-bit OS,
                                          Apple Silicon, ARM servers

  -r, --runtime docker|podman|auto
                               Container runtime to use on the target.
                               (default: auto; prefers Docker, falls back to
                               Podman, and can install Podman with
                               --install-podman).

  -d, --install-dir DIR        Directory for the wrapper on the target
                               (default: ~/bin).

  -s, --system-bin             Install the wrapper to /usr/local/bin instead
                               of ~/bin. Requires sudo on the target.

  --no-install                 Only stage the tarball and wrapper on the
                               target; do not install the wrapper or load the
                               image. Files are placed in:
                               ~/.cache/pi-in-docker-ship/

  --install-podman             If no container runtime is found on the target,
                               automatically install Podman using apt-get,
                               dnf, or yum.

  -h, --help                   Show this help and exit.

Examples:
  ship-pi-in-docker.sh wright@ercam
  ship-pi-in-docker.sh -a arm64 pi@raspberrypi.local
  ship-pi-in-docker.sh -a amd64 --install-podman admin@newserver
  ship-pi-in-docker.sh -a arm64 --no-install pi@raspberrypi.local

What this script does on the target:
  1. Detects (or asks for) the remote architecture.
  2. Builds the matching image locally if it is not already present.
  3. Saves the image as a gzip-compressed tarball.
  4. Copies the tarball and the pi-in-docker wrapper to the target.
  5. Detects Docker or Podman; with --install-podman it installs Podman if
     neither is found.
  6. Adds the remote user to the docker group when Docker is used.
  7. Loads the image into Docker/Podman.
  8. Installs the wrapper to ~/bin (or /usr/local/bin with --system-bin).

After running this script, you still need to copy your pi agent configuration
and credentials to the target. The image ships only the runtime, never your
personal settings or secrets.

Copy tracked pi config to the target:

  cd ~/.pi
  git ls-files | tar -czf - -T - | \
    ssh user@target "mkdir -p ~/.pi && cd ~/.pi && tar -xzf -"

Copy credentials to the target:

  ssh -t user@target "mkdir -p ~/.pi/agent && chmod 700 ~/.pi/agent"
  scp ~/.pi/agent/auth.json user@target:~/.pi/agent/auth.json
  ssh -t user@target "chmod 600 ~/.pi/agent/auth.json"

Or, instead of copying auth.json, log in fresh on the target:

  pi-in-docker
  /login github-copilot
  /login google
  /login kimi.ai
  /login spark

First run on the target:

  pi-in-docker --version
  pi-in-docker -p "hello from $(hostname)"

Notes:
  - If the target cannot resolve LAN hostnames such as spark:12001 from inside
    the container, run pi with PI_NETWORK=host:

      PI_NETWORK=host pi-in-docker

  - The arm64 image must be built on this host with binfmt/QEMU emulation, or
    built natively on an ARM64 machine. If make build-arm64 fails with
    "exec format error", your build host lacks ARM emulation.

  - This script never writes to /usr/local/bin unless you use --system-bin.

EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--arch)
            ARCH="$2"; shift 2 ;;
        -r|--runtime)
            RUNTIME="$2"; shift 2 ;;
        -d|--install-dir)
            INSTALL_DIR="$2"; shift 2 ;;
        -s|--system-bin)
            SYSTEM_BIN=true; shift ;;
        --no-install)
            NO_INSTALL=true; shift ;;
        --install-podman)
            INSTALL_PODMAN=true; shift ;;
        -h|--help)
            show_help; exit 0 ;;
        --)
            shift; break ;;
        -*)
            echo "Unknown option: $1" >&2
            show_help >&2
            exit 1 ;;
        *)
            if [[ -z "$TARGET" ]]; then
                TARGET="$1"; shift
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    show_help >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

detect_target_arch() {
    local arch
    arch="$(ssh "$TARGET" 'uname -m')"
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}

build_if_missing() {
    local tag="$1"
    if ! docker image inspect "$tag" >/dev/null 2>&1; then
        echo "Image $tag not found locally; building..."
        case "$ARCH" in
            amd64) make -C "$SCRIPT_DIR" build-amd64 ;;
            arm64) make -C "$SCRIPT_DIR" build-arm64 ;;
            *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
        esac
    fi
}

export_tarball() {
    local tag="$1"
    local out="$2"
    echo "Exporting $tag to $out..."
    mkdir -p "$(dirname "$out")"
    docker save "$tag" | gzip > "$out"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ "$ARCH" == "auto" ]]; then
    echo "Detecting target architecture..."
    ARCH="$(detect_target_arch)"
    echo "Target architecture: $ARCH"
fi

TAG="${DEFAULT_REGISTRY}/${DEFAULT_NAME}:${DEFAULT_VERSION}-${ARCH}"
TARBALL="${SCRIPT_DIR}/dist/pi-in-docker-${DEFAULT_VERSION}-${ARCH}.tar.gz"
WRAPPER="${SCRIPT_DIR}/pi-in-docker"

build_if_missing "$TAG"
export_tarball "$TAG" "$TARBALL"

STAGE_DIR="~/.cache/pi-in-docker-ship"

# Build the remote install script.
REMOTE_SCRIPT=$(cat <<EOF
set -euo pipefail

ARCH="$ARCH"
TAG="$TAG"
TARBALL="\$HOME/.cache/pi-in-docker-ship/pi-in-docker-${DEFAULT_VERSION}-${ARCH}.tar.gz"
WRAPPER_SRC="\$HOME/.cache/pi-in-docker-ship/pi-in-docker"

mkdir -p "\$HOME/.cache/pi-in-docker-ship"

# Detect or install container runtime.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    RUNTIME="docker"
    GROUP="docker"
elif command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
    GROUP="\$(id -gn)"
else
    if $INSTALL_PODMAN; then
        echo "No container runtime found; installing Podman..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y podman
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y podman
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y podman
        else
            echo "Could not install podman: no supported package manager found." >&2
            exit 1
        fi
        RUNTIME="podman"
        GROUP="\$(id -gn)"
    else
        echo "No container runtime found. Re-run with --install-podman or install Docker/Podman manually." >&2
        exit 1
    fi
fi

# Add user to the appropriate group.
if [[ "\$RUNTIME" == "docker" ]]; then
    if ! groups "\$USER" | grep -q '\bdocker\b'; then
        echo "Adding \$USER to docker group..."
        sudo usermod -aG docker "\$USER"
        echo "Please log out and back in for the group change to take effect, then re-run."
        exit 0
    fi
fi

# Load image.
echo "Loading image from \$TARBALL..."
if [[ "\$RUNTIME" == "docker" ]]; then
    docker load < "\$TARBALL"
else
    podman load < "\$TARBALL"
fi

# Install wrapper.
if $NO_INSTALL; then
    echo "Skipping wrapper install (--no-install)."
    echo "Tarball and wrapper staged at: \$HOME/.cache/pi-in-docker-ship"
    exit 0
fi

if $SYSTEM_BIN; then
    DEST="/usr/local/bin/pi-in-docker"
    echo "Installing wrapper to \$DEST (requires sudo)..."
    sudo cp "\$WRAPPER_SRC" "\$DEST"
    sudo chmod 755 "\$DEST"
else
    DEST="$INSTALL_DIR"
    echo "Installing wrapper to \$DEST..."
    mkdir -p "\$DEST"
    cp "\$WRAPPER_SRC" "\$DEST/pi-in-docker"
    chmod 755 "\$DEST/pi-in-docker"
    if [[ ":\$PATH:" != *":\$DEST:"* ]]; then
        echo "Warning: \$DEST is not in your PATH. Adding it to ~/.bashrc..."
        printf '\\n# pi-in-docker wrapper\\nexport PATH=\"\\$PATH:%s\"\\n' "\$DEST" >> "\$HOME/.bashrc"
        echo "Please run 'source ~/.bashrc' or log out/back in for the change to take effect."
    fi
fi

echo "Done."
EOF
)

echo "Copying tarball and wrapper to ${TARGET}..."
ssh "$TARGET" "mkdir -p ${STAGE_DIR}"
scp "$TARBALL" "$WRAPPER" "${TARGET}:${STAGE_DIR}/"

echo "Running remote install script..."
ssh -t "$TARGET" "$REMOTE_SCRIPT"
