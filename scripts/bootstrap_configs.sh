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

if [ "$#" -lt 4 ]; then
  echo "❌ Missing required arguments"
  echo "Usage: $0 [-y] <api_url> <email> <password> <config_dir>"
  echo "Options:"
  echo "  -y    Non-interactive mode (skip confirmation)"
  exit 1
fi

API_URL="$1"
EMAIL="$2"
PASSWORD="$3"
CONFIG_DIR="$4"
LOGS_URL="$5"

# Validate config directory
if [ ! -d "$CONFIG_DIR" ]; then
  echo "❌ Config directory not found: $CONFIG_DIR"
  exit 1
fi

echo "📝 Using config directory: $CONFIG_DIR"
echo "📝 Using login $EMAIL"

if $INTERACTIVE; then
  echo "📝 Do you want to bootstrap configs? [y/N]"
  read -p "Continue? [y/N] " answer
  if [[ ! $answer =~ ^[Yy]$ ]]; then
    echo "⏭️ Configs bootstrap skipped"
    exit 0
  fi
fi

# Function to process JSON files and replace variables
process_json_file() {
  local input_file="$1"
  local output_file="${input_file}.tmp"

  if [ ! -f "$input_file" ]; then
    echo "⚠️ Input file not found: $input_file"
    return 1
  fi

  cat "$input_file" | \
    sed "s|@@LOGS_URL@@|${LOGS_URL}|g" \
    > "$output_file"

  mv "$output_file" "$input_file"
}

config_exists() {
  local name=$1
  local type=$2
  local response

  response=$(curl -s "$API_URL/api/v2/config/" -b ./tmp/cookies.txt)

  if command -v jq >/dev/null 2>&1; then
    echo "$response" | jq -e ".[] | select(.name == \"$name\" and .type == \"$type\")" >/dev/null
  else
    # Fallback if jq is not available
    echo "$response" | grep -q "\"name\": \"$name\", \"type\": \"$type\""
  fi
  return $?
}

create_config() {
  local type=$1
  local name=$2
  local file=$3

  if [ ! -f "$file" ]; then
    echo "⚠️ Config file not found: $file, skipping..."
    return 0
  fi

  if config_exists "$name" "$type"; then
    echo "⏭️ Config '$name' ($type) already exists, skipping..."
    return 0
  fi

  # Process JSON file before creating config
  process_json_file "$file"

  echo "📝 Creating $type config '$name' from $file..."
  content=$(cat "$file")

  response=$(curl -s "$API_URL/api/v2/config/" \
    -H 'Content-Type: application/json' \
    -b ./tmp/cookies.txt \
    --data-raw "{
      \"type\": \"$type\",
      \"name\": \"$name\",
      \"description\": \"$name Configuration\",
      \"is_active\": true,
      \"content\": $content
    }")

  if echo "$response" | grep -q "id"; then
    echo "✅ Successfully created $name config"
  else
    echo "❌ Failed to create $name config"
    echo "Response: $response"
    exit 1
  fi
}

# Define config files to process
config_names=("report" "meta" "tags" "references" "per_conf")
config_files=("report.json" "meta.json" "tags.json" "references.json" "per_conf.json")

# Process each config
for i in "${!config_names[@]}"; do
  name="${config_names[$i]}"
  file="$CONFIG_DIR/${config_files[$i]}"
  type="global"
  if [ "$name" = "report" ]; then
    type="report"
  fi
  create_config "$type" "$name" "$file"
done

echo "✅ All configs processed successfully!" 