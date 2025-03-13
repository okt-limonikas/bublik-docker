#!/bin/bash

# Accept data directory as parameter
DATA_DIR=${1:-$BUBLIK_DOCKER_DATA_DIR}

# Create and setup data directories
echo "📝 Creating docker data directory..."
if [ -z "${DATA_DIR}" ]; then
    echo -e "\033[0;31m❌ Data directory not specified. Please set BUBLIK_DOCKER_DATA_DIR or provide as parameter\033[0m"
    exit 1
fi

# Get current user's UID and GID
HOST_UID=$(id -u)
HOST_GID=$(id -g)

if [ "$EUID" -ne 0 ]; then
    sudo mkdir -p "${DATA_DIR}/te-logs/"{logs,incoming,bad} || {
        echo -e "\033[0;31m❌ Failed to create directories in ${DATA_DIR}\033[0m"
        exit 1
    }
    
    # Set ownership using host UID/GID
    sudo chown -R ${HOST_UID}:${HOST_GID} "${DATA_DIR}" || {
        echo -e "\033[0;31m❌ Failed to set ownership for ${DATA_DIR}\033[0m"
        exit 1
    }
    
    # Set permissions to allow both host user and container to access
    sudo chmod -R 2775 "${DATA_DIR}/te-logs" || {
        echo -e "\033[0;31m❌ Failed to set permissions for ${DATA_DIR}\033[0m"
        exit 1
    }
else
    mkdir -p "${DATA_DIR}/te-logs/"{logs,incoming,bad} || {
        echo -e "\033[0;31m❌ Failed to create directories in ${DATA_DIR}\033[0m"
        exit 1
    }
    
    # Set ownership using host UID/GID
    chown -R ${HOST_UID}:${HOST_GID} "${DATA_DIR}" || {
        echo -e "\033[0;31m❌ Failed to set ownership for ${DATA_DIR}\033[0m"
        exit 1
    }
    
    # Set permissions to allow both host user and container to access
    chmod -R 2775 "${DATA_DIR}/te-logs" || {
        echo -e "\033[0;31m❌ Failed to set permissions for ${DATA_DIR}\033[0m"
        exit 1
    }
fi

echo "✅ Docker data directory created at ${DATA_DIR}"
echo "✅ Docker environment setup complete!" 