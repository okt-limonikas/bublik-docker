#!/bin/bash
if [ ! -f ".env" ]; then
  echo "📝 Creating .env from template..."
  cp .env.example .env
  
  # Set HOST_UID and HOST_GID in .env file
  echo "📝 Adding HOST_UID and HOST_GID to .env file..."
  echo "" >> .env
  echo "# Host user/group settings for container permissions" >> .env
  echo "HOST_UID=$(id -u)" >> .env
  echo "HOST_GID=$(id -g)" >> .env
  echo "UMASK=022" >> .env
  
  echo "✅ Created .env file with HOST_UID=$(id -u) and HOST_GID=$(id -g)"
else
  echo "⏭️ Using existing .env file"
  
  # Check if HOST_UID and HOST_GID are already in .env
  if ! grep -q "HOST_UID" .env || ! grep -q "HOST_GID" .env || ! grep -q "UMASK" .env; then
    echo "📝 Adding missing HOST_UID, HOST_GID, or UMASK to .env file..."
    
    # Add a blank line if needed
    echo "" >> .env
    echo "# Host user/group settings for container permissions" >> .env
    
    # Add HOST_UID if missing
    if ! grep -q "HOST_UID" .env; then
      echo "HOST_UID=$(id -u)" >> .env
    fi
    
    # Add HOST_GID if missing
    if ! grep -q "HOST_GID" .env; then
      echo "HOST_GID=$(id -g)" >> .env
    fi
    
    # Add UMASK if missing
    if ! grep -q "UMASK" .env; then
      echo "UMASK=022" >> .env
    fi
    
    echo "✅ Updated .env file with host user/group settings"
  fi
  
  echo "ℹ️  To reset to defaults, remove .env and run setup again"
fi