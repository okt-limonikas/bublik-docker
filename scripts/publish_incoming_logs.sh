#!/bin/bash

COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-bublik}
BUBLIK_DOCKER_DATA_DIR=${BUBLIK_DOCKER_DATA_DIR:-./data}

echo "🔄 Publishing logs..."
docker exec -it "${COMPOSE_PROJECT_NAME}-te-log-server" /bin/bash -c "/home/te-logs/bin/publish-incoming-logs"