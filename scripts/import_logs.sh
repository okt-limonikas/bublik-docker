#!/bin/bash

# Parse command line arguments
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

FILENAME=$(basename "$FILE")
echo "📝 Copying $FILENAME to container..."
docker cp "$FILE" te-log-server:/home/te-logs/incoming/

echo "🔄 Processing logs..."

# Fix permissions before processing
docker exec te-log-server chown -R www-data:www-data /home/te-logs/incoming/
docker exec -it te-log-server /bin/bash -c "cd /home/te-logs/bin && ./publish-incoming-logs"
# Fix permissions after processing
docker exec te-log-server chown -R www-data:www-data /home/te-logs/logs/
docker exec te-log-server chmod -R 755 /home/te-logs/logs/ 