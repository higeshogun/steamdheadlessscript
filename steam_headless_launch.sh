#!/bin-bash
set -euxo pipefail

# --- 1. User Configuration ---
# We will get TAILSCALE_AUTH_KEY from the Vast.ai template's
# environment variables.

# --- 2. System Preparation ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git

# --- 3. Install Tailscale ---
echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# --- 4. Start Tailscale ---
echo "Starting Tailscale and logging in..."
if [ -z "$TAILSCALE_AUTH_KEY" ] || [ "$TAILSCALE_AUTH_KEY" == "YOUR_TAILSCALE_AUTH_KEY_HERE" ]; then
    echo "ERROR: TAILSCALE_AUTH_KEY is not set. Please set it in the Vast.ai template."
    exit 1
fi

tailscale up --authkey=${TAILSCALE_AUTH_KEY} --ssh

# --- 5. Clone Steam-Headless Repo ---
echo "Cloning Steam-Headless repository..."
git clone https://github.com/Steam-Headless/docker-steam-headless.git /opt/docker-steam-headless
cd /opt/docker-steam-headless

# --- 6. Launch the Docker Container ---
echo "Pulling and starting the Steam-Headless container..."
docker compose -f docs/compose-files/docker-compose.nvidia.yml pull
docker compose -f docs/compose-files/docker-compose.nvidia.yml up -d

echo "--- Setup Complete ---"
