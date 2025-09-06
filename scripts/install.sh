#!/usr/bin/env bash

# --- Helper Functions ---
update_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >>.env
  fi
}

# --- 1. Install dependencies ---
echo "[*] Installing dependencies: curl, jq, git, task"
sudo apt update -y
sudo apt install -y curl jq git

if ! command -v task &>/dev/null; then
  sudo sh -c "$(curl -sL https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
fi

# --- 2. Install Docker ---
if ! command -v docker &>/dev/null; then
  echo "[*] Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo groupadd -f docker
  sudo usermod -aG docker "$USER"
  newgrp docker
fi

# --- 3. Clone repository ---
if [ ! -d "bublik-docker" ]; then
  echo "[*] Cloning Bublik Repository..."
  git clone --recurse-submodules https://github.com/ts-factory/bublik-docker.git
fi

cd bublik-docker || {
  echo "[!] Failed to change to bublik-docker directory"
  exit 1
}

# --- 4. Setup .env file ---
if [ ! -f ".env" ]; then
  echo "[*] Running task setup..."
  task setup
fi

# --- 5. Generate secret key ---
echo "[*] Generating secret key..."
SECRET_KEY=$(openssl rand -base64 50 | tr -d '/+=\n')
update_env "SECRET_KEY" "$SECRET_KEY"

# --- 6. Ask user for Bublik FQDN ---
read -rp "Enter Bublik FQDN (default: http://localhost): " BUBLIK_FQDN
BUBLIK_FQDN=${BUBLIK_FQDN:-http://localhost}
update_env "BUBLIK_FQDN" "$BUBLIK_FQDN"

# --- 7. Ask user for PROXY port ---
read -rp "Enter Proxy Port (default: 80): " BUBLIK_DOCKER_PROXY_PORT
BUBLIK_DOCKER_PROXY_PORT=${BUBLIK_DOCKER_PROXY_PORT:-80}
update_env "BUBLIK_DOCKER_PROXY_PORT" "$BUBLIK_DOCKER_PROXY_PORT"

# --- 8. Ask user for Data Directory ---
read -rp "Enter Data Directory (default: /opt/bublik/data): " BUBLIK_DOCKER_DATA_DIR
BUBLIK_DOCKER_DATA_DIR=${BUBLIK_DOCKER_DATA_DIR:-/opt/bublik/data}
update_env "BUBLIK_DOCKER_DATA_DIR" "$BUBLIK_DOCKER_DATA_DIR"

# --- 9. Create data directory if it doesn't exist ---
echo "[*] Creating data directory: ${BUBLIK_DOCKER_DATA_DIR}"
sudo mkdir -p "$BUBLIK_DOCKER_DATA_DIR"
sudo chown "$USER:$USER" "$BUBLIK_DOCKER_DATA_DIR"

# --- 10. Start application ---
echo "[*] Starting Bublik..."
if command -v task &>/dev/null; then
  task up
else
  echo "[!] Task command not found. Please run 'task up' manually after the script completes."
fi
