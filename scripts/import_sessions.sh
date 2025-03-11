#!/bin/bash

# Parse command line arguments
if [ "$#" -lt 2 ]; then
  echo "❌ Missing required arguments"
  echo "Usage: $0 <api_url> <import_file>"
  exit 1
fi

API_URL="$1"
IMPORT_FILE="$2"

if [ ! -f "$IMPORT_FILE" ]; then
  echo "❌ Import file not found: $IMPORT_FILE"
  exit 1
fi

echo "📝 Using import file: $IMPORT_FILE"
echo "📝 Import test sessions from $IMPORT_FILE? [y/N]"
read -p "Continue? [y/N] " answer
if [[ ! $answer =~ ^[Yy]$ ]]; then
  echo "⏭️ Import skipped"
  exit 0
fi

echo "📝 Starting test sessions import..."
# Make sure file ends with newline and read each URL
sed -e '$a\' "$IMPORT_FILE" | while read -r url; do
  # Skip empty lines and comments
  [[ -z "$url" || "$url" =~ ^[[:space:]]*# ]] && continue

  echo "🔄 Starting import: $url"
  curl -s "$API_URL/api/v2/importruns/source/?url=$url" \
    -H 'Content-Type: application/json' \
    -b cookies.txt >/dev/null

  sleep 1
  echo "✅ Import started"
done

echo "✅ All imports have been queued!" 