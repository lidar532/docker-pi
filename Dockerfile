FROM node:24-bookworm-slim

# Install general tools that pi and its bash tool expect.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates git ripgrep make build-essential ssh curl jq \
 && rm -rf /var/lib/apt/lists/*

# Install the latest pi from pi.dev. Node 24 is already provided by the
# base image, so no host-side Node/npm pollution is possible.
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Create a default user that matches a common host UID/GID (1000:1000).
# The runtime wrapper overrides this with the actual host user via --user.
RUN useradd -u 1000 -d /home/piuser -s /bin/bash piuser 2>/dev/null || true \
 && mkdir -p /home/piuser/.pi/agent \
 && chown -R 1000:1000 /home/piuser

WORKDIR /host
ENTRYPOINT ["pi"]
