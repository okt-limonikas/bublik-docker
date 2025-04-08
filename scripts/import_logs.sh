#!/bin/bash

if [ "$#" -lt 1 ]; then
  echo "❌ Missing required arguments"
  echo "Usage: $0 <file.tar>"
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
fi

COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-bublik}
BUBLIK_DOCKER_DATA_DIR=${BUBLIK_DOCKER_DATA_DIR:-./data}

TARGET_DIR="${BUBLIK_DOCKER_DATA_DIR}/logs/incoming"
mkdir -p "$TARGET_DIR"

FILENAME=$(basename "$FILE")
echo "📝 Copying $FILENAME to $TARGET_DIR..."
cp "$FILE" "$TARGET_DIR/"

echo "🔄 Processing logs..."
CONTAINER_NAME=$(docker ps --format '{{.Names}}' | grep "${COMPOSE_PROJECT_NAME}-te-log-server")
docker exec -it "${CONTAINER_NAME}" /bin/bash -c "/home/te-logs/bin/publish-incoming-logs"
