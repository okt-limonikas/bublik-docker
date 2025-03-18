#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS
OS="$(uname -s)"
IS_MACOS=false
if [ "$OS" = "Darwin" ]; then
    IS_MACOS=true
fi

ask_yes_no() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

check_system_deps() {
  local missing_deps=()

  if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
  fi
  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  if [ ${#missing_deps[@]} -eq 0 ]; then
    echo "✅ All system dependencies are installed"
    return 0
  fi

  echo -e "${RED}⚠️  Missing dependencies: ${missing_deps[*]}${NC}"
  if ask_yes_no "Would you like to install missing dependencies?"; then
    if [ "$EUID" -ne 0 ]; then
      echo "🔐 Requesting sudo privileges to install packages..."
      sudo apt-get update
      sudo apt-get install -y "${missing_deps[@]}"
    else
      apt-get update
      apt-get install -y "${missing_deps[@]}"
    fi
    echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
  else
    echo -e "${RED}⚠️  Warning: Missing dependencies may cause issues${NC}"
    exit 1
  fi
}

check_docker_deps() {
  local need_docker=false
  local need_compose=false

  if ! command -v docker &> /dev/null; then
    need_docker=true
    echo -e "${RED}⚠️  Docker is not installed!${NC}"
    
    if ask_yes_no "Would you like to install Docker?"; then
      if [ "$IS_MACOS" = true ]; then
        echo -e "${YELLOW}ℹ️  On macOS, Docker needs to be installed manually via Docker Desktop${NC}"
        echo "📚 Visit: https://docs.docker.com/desktop/install/mac/"
        exit 1
      else
        echo "📥 Installing Docker using convenience script..."
        if [ "$EUID" -ne 0 ]; then
          curl -fsSL https://get.docker.com -o get-docker.sh
          sudo sh get-docker.sh
          sudo systemctl start docker
          sudo systemctl enable docker
          sudo usermod -aG docker $USER
        else
          curl -fsSL https://get.docker.com -o get-docker.sh
          sh get-docker.sh
          systemctl start docker
          systemctl enable docker
          usermod -aG docker $USER
        fi
        rm get-docker.sh
        echo -e "${GREEN}✅ Docker installed successfully${NC}"
        echo "🔄 Please log out and back in for group changes to take effect"
      fi
    else
      echo -e "${YELLOW}ℹ️  Manual installation instructions:${NC}"
      if [ "$IS_MACOS" = true ]; then
        echo "📚 Visit: https://docs.docker.com/desktop/install/mac/"
      else
        echo "📚 Visit: https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script"
      fi
      exit 1
    fi
  fi

  if ! docker compose version &> /dev/null; then
    need_compose=true
    echo -e "${RED}⚠️  Docker Compose plugin is not installed!${NC}"
    
    if ask_yes_no "Would you like to install Docker Compose plugin?"; then
      if [ "$IS_MACOS" = true ]; then
        echo -e "${YELLOW}ℹ️  On macOS, Docker Compose comes bundled with Docker Desktop${NC}"
        echo "📚 Please install Docker Desktop from: https://docs.docker.com/desktop/install/mac/"
        exit 1
      else
        if [ "$EUID" -ne 0 ]; then
          sudo apt-get update
          sudo apt-get install -y docker-compose-plugin
        else
          apt-get update
          apt-get install -y docker-compose-plugin
        fi
        echo -e "${GREEN}✅ Docker Compose plugin installed successfully${NC}"
      fi
    else
      echo -e "${YELLOW}ℹ️  Manual installation instructions:${NC}"
      echo "📚 Visit: https://docs.docker.com/compose/install/linux/"
      exit 1
    fi
  fi

  # Check if user is in docker group (skip for macOS as Docker Desktop handles permissions)
  if [ "$IS_MACOS" = false ]; then
    if ! groups | grep -q "docker"; then
      echo -e "${YELLOW}⚠️  Your user is not in the docker group!${NC}"
      if ask_yes_no "Would you like to add your user to the docker group?"; then
        if [ "$EUID" -ne 0 ]; then
          sudo groupadd docker 2>/dev/null || true
          sudo usermod -aG docker $USER
        else
          groupadd docker 2>/dev/null || true
          usermod -aG docker $USER
        fi
        echo -e "${GREEN}✅ User added to docker group${NC}"
        echo -e "${YELLOW}⚠️  For security reasons, you must log out and log back in${NC}"
        echo -e "${YELLOW}⚠️  for the group changes to take effect.${NC}"
        echo -e "${GREEN}👉 Please:${NC}"
        echo -e "  1. Log out of your session"
        echo -e "  2. Log back in"
        echo -e "  3. Run the command again"
        exit 1
      else
        echo -e "${YELLOW}⚠️  You'll need to use sudo for docker commands${NC}"
      fi
    else
      echo "✅ User is in docker group"
    fi
  fi

  # Check if Docker daemon is running
  if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}⚠️  Docker daemon is not running!${NC}"
    
    if [ "$IS_MACOS" = true ]; then
      echo -e "${YELLOW}ℹ️  Please start Docker Desktop application${NC}"
      exit 1
    else
      # Create docker group if it doesn't exist
      if ! getent group docker >/dev/null; then
        echo "Creating docker group..."
        if [ "$EUID" -ne 0 ]; then
          sudo groupadd docker || {
            echo -e "${RED}❌ Failed to create docker group${NC}"
            exit 1
          }
        else
          groupadd docker || {
            echo -e "${RED}❌ Failed to create docker group${NC}"
            exit 1
          }
        fi
        echo -e "${GREEN}✅ Docker group created successfully${NC}"
      fi

      if [ "$EUID" -ne 0 ]; then
        echo "🔐 Requesting sudo privileges to start Docker..."
        if sudo systemctl start docker; then
          echo -e "${GREEN}✅ Docker daemon started successfully${NC}"
        else
          echo -e "${RED}❌ Failed to start Docker daemon${NC}"
          exit 1
        fi
      else
        if systemctl start docker; then
          echo -e "${GREEN}✅ Docker daemon started successfully${NC}"
        else
          echo -e "${RED}❌ Failed to start Docker daemon${NC}"
          exit 1
        fi
      fi
    fi
  fi

  if ! $need_docker && ! $need_compose; then
    echo "✅ Docker $(docker --version) is installed"
    echo "✅ Docker Compose $(docker compose version --short) is installed"
    echo "✅ Docker daemon is running"
  fi
}

case "$1" in
  "system")
    check_system_deps
    ;;
  "docker")
    check_docker_deps
    ;;
  *)
    echo "Usage: $0 {system|docker}"
    exit 1
    ;;
esac 