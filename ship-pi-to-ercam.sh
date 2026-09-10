#!/usr/bin/env bash
set -euo pipefail

# ship-pi-to-ercam.sh
# Build the pi Docker image locally, export it, and stage it on ercam.
# This script does NOT install anything into /usr/local/bin on ercam;
# it only copies the image tarball and wrapper to /tmp. The user can
# then decide whether to install the wrapper system-wide.

IMAGE="${PI_DOCKER_IMAGE:-pi-ercam:latest}"
TARBALL="pi-ercam.tar.gz"
REMOTE="${PI_ERCAM_HOST:-wright@ercam}"
REMOTE_TMP_DIR="/tmp/docker-pi-ship"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
    echo "ERROR: Dockerfile not found in $SCRIPT_DIR"
    exit 1
fi

echo "==> Building image: $IMAGE"
docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

echo "==> Exporting image to $TARBALL"
docker save "$IMAGE" | gzip > "$SCRIPT_DIR/$TARBALL"

echo "==> Staging files on $REMOTE:$REMOTE_TMP_DIR"
ssh -o BatchMode=yes "$REMOTE" "mkdir -p $REMOTE_TMP_DIR"
scp "$SCRIPT_DIR/$TARBALL" "$REMOTE:$REMOTE_TMP_DIR/"
scp "$SCRIPT_DIR/pi.in.docker" "$REMOTE:$REMOTE_TMP_DIR/"

echo ""
echo "==> Done. Files are on $REMOTE:$REMOTE_TMP_DIR"
echo ""
echo "Prerequisites on ercam:"
echo "  1. Add your user to the docker group so you can run Docker without sudo:"
echo "       sudo usermod -aG docker \$USER"
echo "     Then log out and back in (or run 'newgrp docker')."
echo ""
echo "Next steps on ercam:"
echo "  ssh -t $REMOTE"
echo "  docker load < $REMOTE_TMP_DIR/$TARBALL"
echo "  # optional: install wrapper system-wide"
echo "  sudo mv $REMOTE_TMP_DIR/pi.in.docker /usr/local/bin/pi.in.docker"
echo "  sudo chmod 755 /usr/local/bin/pi.in.docker"
echo ""
echo "To run locally without installing system-wide:"
echo "  ./pi.in.docker"
echo ""
echo "To update to the latest pi from pi.dev, just re-run this script."
