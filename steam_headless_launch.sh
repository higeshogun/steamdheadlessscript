#!/bin/bash
set -e

# --- CONFIG ---
SERVICE_DIR=/opt/container-services/steam-headless
DATA_DIR=/opt/container-data/steam-headless
GAMES_DIR=/mnt/games
IMAGE_NAME=steam-headless-nvenc

# --- PREP DIRECTORIES ---
mkdir -p $SERVICE_DIR $DATA_DIR/home $DATA_DIR/.X11-unix $DATA_DIR/pulse $GAMES_DIR

# --- ENV FILE ---
cat > $SERVICE_DIR/.env <<EOF
TZ=Asia/Tokyo
PUID=1000
PGID=1000
UMASK=022
MODE=desktop
ENABLE_STEAM=true
ENABLE_SUNSHINE=true
HOME_DIR=/home/steam
SHARED_SOCKETS_DIR=/tmp/.X11-unix
GAMES_DIR=$GAMES_DIR
WEB_UI_MODE=novnc
PORT_NOVNC_WEB=8083
SUNSHINE_USER=steam
SUNSHINE_PASS=steam
SUNSHINE_PORT=47989
SUNSHINE_WEB_PORT=47990
SUNSHINE_RESOLUTION=1920x1080
SUNSHINE_REFRESH_RATE=60
SHM_SIZE=2g
USER_LOCALES=en_US.UTF-8
DISPLAY=:0
USER_PASSWORD=steam
ENABLE_VNC_AUDIO=true
NEKO_NAT1TO1=127.0.0.1
STEAM_ARGS=""
NVIDIA_VISIBLE_DEVICES=all
NVIDIA_DRIVER_VERSION=575
EOF

# --- DOCKERFILE (NVENC layer) ---
cat > $SERVICE_DIR/Dockerfile <<'EOF'
FROM josh5/steam-headless:latest

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ffmpeg \
      nvidia-cuda-toolkit && \
    rm -rf /var/lib/apt/lists/*
EOF

# --- COMPOSE FILE ---
cat > $SERVICE_DIR/docker-compose.yml <<EOF
services:
  steam-headless:
    build: .
    image: $IMAGE_NAME:latest
    container_name: steam-headless
    restart: unless-stopped
    env_file: .env
    volumes:
      - $DATA_DIR/home:/home/steam
      - $DATA_DIR/.X11-unix:/tmp/.X11-unix
      - $DATA_DIR/pulse:/run/pulse
      - $GAMES_DIR:/mnt/games
      - /usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:ro
      - /usr/lib/nvidia:/usr/lib/nvidia:ro
    ports:
      - "8083:8083"
      - "47989:47989/tcp"
      - "47989:47989/udp"
      - "47990:47990/tcp"
      - "47998-48010:47998-48010/udp"
      - "22:22"
    stdin_open: true
    tty: true
EOF

# --- BUILD & LAUNCH ---
cd $SERVICE_DIR
docker compose down || true
docker compose build
docker compose up -d

echo "✅ Steam-Headless with NVENC + Sunshine is up!"
echo "Check NVENC: docker exec -it steam-headless ffmpeg -encoders | grep nvenc"
echo "Check Sunshine: docker exec -it steam-headless ps aux | grep sunshine"
