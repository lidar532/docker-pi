FROM node:24-bookworm-slim

# Install general tools that pi and its bash tool expect.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates git ripgrep make build-essential ssh curl \
 && rm -rf /var/lib/apt/lists/*

# Install the latest pi from pi.dev. Node 24 is already provided by the
# base image, so no host-side Node/npm pollution is possible.
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Create a user that matches the expected host UID/GID (wright@ercam is 1000:1000).
# This is a fallback; the runtime wrapper will override with the actual host user.
RUN useradd -u 1000 -d /home/wright -s /bin/bash wright 2>/dev/null || true \
 && mkdir -p /home/wright/.pi/agent \
 && chown -R 1000:1000 /home/wright

WORKDIR /host
ENTRYPOINT ["pi"]
