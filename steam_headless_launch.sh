#!/bin/bash
set -e

# --- 0. Config knobs (edit as needed) ---
GPU_TEMPLATE="nvidia"            # options: nvidia | amd+intel
TZ_VAL="Asia/Tokyo"
SUNSHINE_USER="admin"
SUNSHINE_PASS="changeme123"      # change this
DEFAULT_RES="1920x1080"
DEFAULT_HZ="60"

# --- 1. System prep ---
apt-get update
apt-get install -y docker.io docker-compose git nano openssh-server python3 curl jq

systemctl enable docker
systemctl start docker
systemctl enable ssh
systemctl start ssh

# --- 2. Folders ---
mkdir -p /opt/container-services/steam-headless
mkdir -p /opt/container-data/steam-headless/{home,.X11-unix,pulse}
mkdir -p /mnt/games
chown -R $(id -u):$(id -g) /opt/container-services/steam-headless /opt/container-data/steam-headless /mnt/games
chmod -R 777 /mnt/games

# --- 3. Repo ---
if [ ! -d "/opt/container-services/steam-headless/docker-steam-headless" ]; then
  git clone https://github.com/Steam-Headless/docker-steam-headless.git /opt/container-services/steam-headless/docker-steam-headless
fi

# --- 4. Compose template selection ---
if [ "$GPU_TEMPLATE" = "nvidia" ]; then
  cp /opt/container-services/steam-headless/docker-steam-headless/docs/compose-files/docker-compose.nvidia.yml /opt/container-services/steam-headless/docker-compose.yml
else
  cp /opt/container-services/steam-headless/docker-steam-headless/docs/compose-files/docker-compose.amd+intel.yml /opt/container-services/steam-headless/docker-compose.yml
fi

# --- 5. .env for steam-headless + sunshine ---
cat > /opt/container-services/steam-headless/.env <<EOF
NAME=SteamHeadless
TZ=${TZ_VAL}
PUID=1000
PGID=1000
UMASK=000
MODE=primary

ENABLE_STEAM=true
ENABLE_SUNSHINE=true
ENABLE_EVDEV_INPUTS=true
FORCE_X11_DUMMY_CONFIG=false

HOME_DIR=/opt/container-data/steam-headless/home
SHARED_SOCKETS_DIR=/opt/container-data/steam-headless
GAMES_DIR=/mnt/games

WEB_UI_MODE=vnc
PORT_NOVNC_WEB=8083

SUNSHINE_USER=${SUNSHINE_USER}
SUNSHINE_PASS=${SUNSHINE_PASS}
SUNSHINE_PORT=47989
SUNSHINE_WEB_PORT=47990

# desktop defaults
SUNSHINE_RESOLUTION=${DEFAULT_RES}
SUNSHINE_REFRESH_RATE=${DEFAULT_HZ}
EOF

# --- 6. Ensure ports exposed (append to compose) ---
# Note: This assumes service key is 'steam-headless'. If upstream changes, adjust the service name.
if ! grep -q "47989" /opt/container-services/steam-headless/docker-compose.yml; then
cat >> /opt/container-services/steam-headless/docker-compose.yml <<'EOF'

services:
  steam-headless:
    ports:
      - "8083:8083"                 # VNC Web UI
      - "47989:47989/tcp"           # Sunshine discovery
      - "47989:47989/udp"           # Sunshine discovery/handshake
      - "47990:47990/tcp"           # Sunshine Web UI
      - "47998-48010:47998-48010/udp"  # Sunshine media/input
      - "22:22"                     # SSH inside container (if enabled)
EOF
fi

# --- 7. Launch steam-headless ---
cd /opt/container-services/steam-headless
docker-compose up -d --force-recreate

# --- 8. Pairing helper (optional, one-time PIN relay) ---
# This tiny local endpoint accepts a PIN and relays it to Sunshine's pairing API.
# Usage from your client: curl "http://<vast_ip>:8888/pair?pin=1234"
cat > /opt/container-services/steam-headless/pair_helper.py <<'PYEOF'
import http.server, socketserver, urllib.parse, json, sys
import subprocess

PORT = 8888

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != '/pair':
            self.send_response(404); self.end_headers(); self.wfile.write(b'Not found'); return
        qs = urllib.parse.parse_qs(parsed.query)
        pin = qs.get('pin', [''])[0]
        if not pin or not pin.isdigit():
            self.send_response(400); self.end_headers(); self.wfile.write(b'Provide ?pin=1234'); return

        # Sunshine API: we forward PIN to complete pairing. Implementation may vary by build.
        # Attempt a local API call via curl to Sunshine Web UI.
        try:
            # Example: POST to /api/pair with JSON body {"pin":"1234"}
            # Adjust if your image uses a different endpoint.
            cmd = [
                "curl","-sS","-X","POST","http://127.0.0.1:47990/api/pair",
                "-H","Content-Type: application/json",
                "-d", json.dumps({"pin": pin})
            ]
            out = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode()
            self.send_response(200); self.end_headers(); self.wfile.write(out.encode())
        except subprocess.CalledProcessError as e:
            self.send_response(500); self.end_headers(); self.wfile.write(e.output)
        except Exception as e:
            self.send_response(500); self.end_headers(); self.wfile.write(str(e).encode())

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Pair helper on :{PORT}")
    httpd.serve_forever()
PYEOF

nohup python3 /opt/container-services/steam-headless/pair_helper.py >/var/log/pair_helper.log 2>&1 &

echo "✅ Steam-Headless + Sunshine deployed."
echo "🌐 VNC:        http://<vast_instance_ip>:8083"
echo "🎮 Sunshine:   http://<vast_instance_ip>:47990"
echo "🔑 SSH (host): port 22"
echo "📡 Pair helper: http://<vast_instance_ip>:8888/pair?pin=1234"
echo "🖥️ Defaults:   ${DEFAULT_RES} @ ${DEFAULT_HZ}Hz"
