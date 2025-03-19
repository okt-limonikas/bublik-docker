#!/bin/bash

# Parse command line arguments
INTERACTIVE=true

while getopts "y" opt; do
  case $opt in
    y)
      INTERACTIVE=false
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

if [ "$#" -lt 2 ]; then
  echo "❌ Missing required arguments"
  echo "Usage: $0 [-y] <api_url> <import_file>"
  echo "Options:"
  echo "  -y    Non-interactive mode (skip confirmation)"
  exit 1
fi

API_URL="$1"
IMPORT_FILE="$2"

if [ ! -f "$IMPORT_FILE" ]; then
  echo "❌ Import file not found: $IMPORT_FILE"
  exit 1
fi

echo "📝 Using import file: $IMPORT_FILE"

if $INTERACTIVE; then
  echo "📝 Import test sessions from $IMPORT_FILE? [y/N]"
  read -p "Continue? [y/N] " answer
  if [[ ! $answer =~ ^[Yy]$ ]]; then
    echo "⏭️ Import skipped"
    exit 0
  fi
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