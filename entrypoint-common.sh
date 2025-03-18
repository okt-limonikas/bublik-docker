#!/bin/bash

# Common utility functions for entrypoint scripts

setup_umask() {
    if [ -n "${UMASK}" ]; then
        echo "Setting umask to ${UMASK}"
        umask ${UMASK}
    fi
}

ensure_directory() {
    local dir="$1"
    if [ -n "$dir" ]; then
        mkdir -p "$dir"
    fi
}

setup_permissions() {
    local dirs=("$@")
    
    # Skip if not running as root
    if [ "$(id -u)" -ne 0 ]; then
        echo "Running as user $(id -u):$(id -g), skipping permission adjustment"
        return
    fi
    
    # Get container UID/GID from environment or use defaults
    CONTAINER_UID=${HOST_UID:-1000}
    CONTAINER_GID=${HOST_GID:-1000}
    
    echo "Setting ownership to ${CONTAINER_UID}:${CONTAINER_GID} for directories:"
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            echo "  - $dir"
            chown -R ${CONTAINER_UID}:${CONTAINER_GID} "$dir"
            chmod -R 2775 "$dir"  # Add SGID bit
        fi
    done
}

exec_as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        CONTAINER_UID=${HOST_UID:-1000}
        CONTAINER_GID=${HOST_GID:-1000}
        echo "Executing as user ${CONTAINER_UID}:${CONTAINER_GID}"
        exec gosu ${CONTAINER_UID}:${CONTAINER_GID} "$@"
    else
        # Already running as non-root
        echo "Already running as $(id -u):$(id -g)"
        exec "$@"
    fi
}

setup_service_user() {
    local username="$1"
    local config_file="$2"
    
    if [ "$(id -u)" -ne 0 ]; then
        return
    fi
    
    CONTAINER_UID=${HOST_UID:-1000}
    CONTAINER_GID=${HOST_GID:-1000}
    
    if id -u ${CONTAINER_UID} >/dev/null 2>&1; then
        echo "User with UID ${CONTAINER_UID} already exists, using that user"
        CUSTOM_USER=$(id -nu ${CONTAINER_UID} 2>/dev/null || echo "custom_user")
    else
        echo "Creating custom user with UID ${CONTAINER_UID}"
        CUSTOM_USER="custom_user"
        useradd -u ${CONTAINER_UID} -o -m ${CUSTOM_USER} 2>/dev/null || true
    fi
    
    if getent group ${CONTAINER_GID} >/dev/null 2>&1; then
        echo "Group with GID ${CONTAINER_GID} already exists, using that group"
        CUSTOM_GROUP=$(getent group ${CONTAINER_GID} | cut -d: -f1)
    else
        echo "Creating custom group with GID ${CONTAINER_GID}"
        CUSTOM_GROUP="custom_group"
        groupadd -g ${CONTAINER_GID} -o ${CUSTOM_GROUP} 2>/dev/null || true
    fi
    
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        if [ ! -f "${config_file}.orig" ]; then
            cp "$config_file" "${config_file}.orig"
        fi
        
        sed -i "s/export ${username}_USER=.*/export ${username}_USER=${CUSTOM_USER}/" "$config_file"
        sed -i "s/export ${username}_GROUP=.*/export ${username}_GROUP=${CUSTOM_GROUP}/" "$config_file"
    fi
    
    echo "Service user setup complete: ${CUSTOM_USER}:${CUSTOM_GROUP}"
} 