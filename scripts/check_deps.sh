#!/bin/bash

check_system_deps() {
  echo "🔍 Checking system dependencies..."
  if ! command -v jq &> /dev/null; then
    echo "⚠️  jq is not installed!"
    echo "To install jq:"
    echo "  sudo apt-get install jq"
    exit 1
  fi
  if ! command -v curl &> /dev/null; then
    echo "⚠️  curl is not installed!"
    echo "To install curl:"
    echo "  sudo apt-get install curl"
    exit 1
  fi
  echo "✅ All system dependencies are installed"
}

check_docker_deps() {
  echo "🔍 Checking Docker installation..."
  if ! command -v docker &> /dev/null; then
    echo "⚠️  Docker is not installed!"
    echo ""
    echo "Quick Install (using convenience script):"
    echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
    echo "  sudo sh get-docker.sh"
    echo ""
    echo "📚 For more installation options, visit:"
    echo "  https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script"
    echo ""
    echo "🔧 After installation, don't forget the post-installation steps:"
    echo "  1. Add your user to docker group:"
    echo "     sudo groupadd docker"
    echo "     sudo usermod -aG docker \$USER"
    echo "     newgrp docker"
    echo ""
    echo "  2. Configure Docker to start on boot:"
    echo "     sudo systemctl enable docker.service"
    echo "     sudo systemctl enable containerd.service"
    echo ""
    echo "📚 For detailed post-installation steps, visit:"
    echo "  https://docs.docker.com/engine/install/linux-postinstall/"
    exit 1
  fi

  if ! docker compose version &> /dev/null; then
    echo "⚠️  Docker Compose plugin is not installed!"
    echo "To install Docker Compose plugin:"
    echo "  sudo apt-get install docker-compose-plugin"
    echo ""
    echo "For more installation options, visit:"
    echo "  https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script"
    exit 1
  fi

  # Check if user is in docker group
  if ! groups | grep -q "docker"; then
    echo "⚠️  Your user is not in the docker group!"
    echo "This means you'll need to use sudo for docker commands."
    echo ""
    echo "To run Docker as a non-root user:"
    echo "  sudo groupadd docker"
    echo "  sudo usermod -aG docker \$USER"
    echo "  newgrp docker"
    echo ""
    echo "📚 For more information, visit:"
    echo "  https://docs.docker.com/engine/install/linux-postinstall/"
  else
    echo "✅ User is in docker group"
  fi

  echo "✅ Docker $(docker --version) is installed"
  echo "✅ Docker Compose $(docker compose version --short) is installed"
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