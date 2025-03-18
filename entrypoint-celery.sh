#!/bin/bash

# Source common functions
source /app/bublik/entrypoint-common.sh

# Set umask
setup_umask

# Create required directories
echo "Setting up required directories..."
ensure_directory "${BUBLIK_LOGDIR}"
ensure_directory "${BUBLIK_DOCKER_DATA_DIR}/django-logs"
ensure_directory "${TMPDIR}"

# Set proper permissions for all directories
setup_permissions "${BUBLIK_LOGDIR}" "${BUBLIK_DOCKER_DATA_DIR}/django-logs" "${TMPDIR}"

# Execute command as the specified user
exec_as_user "$@" 