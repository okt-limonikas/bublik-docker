#!/bin/bash

# Parse command line arguments
if [ "$#" -lt 1 ]; then
  echo "❌ Missing required arguments"
  echo "Usage: $0 <api_url>"
  exit 1
fi

API_URL="$1"

echo "🚀 Starting meta-categorization..."
RESPONSE=$(curl -s -X POST -w "\n%{http_code}" "$API_URL/meta_categorization/")
BODY=$(echo "$RESPONSE" | sed '$d')  # Extract response body
STATUS_CODE=$(echo "$RESPONSE" | tail -n1)  # Extract HTTP status code

if [[ "$STATUS_CODE" =~ ^2 ]]; then
  echo "✅ Meta-categorization triggered successfully!"
else
  echo "❌ Failed to trigger meta-categorization (HTTP $STATUS_CODE)"
  echo "🔍 Error response: $BODY"
  exit 1
fi 