#!/bin/bash

if [ ! -f ".env" ]; then
  echo "📝 Creating .env from template..."
  cp .env.local .env
  echo "✅ Created .env file"
else
  echo "⏭️ Using existing .env file"
  echo "ℹ️  To reset to defaults, remove .env and run setup again"
fi

if [ -f "bublik/settings.py" ]; then
  echo "⚠️  Removing existing settings.py..."
  rm bublik/settings.py
fi
echo "📝 Copying docker settings template..."
cp docker-settings.py.template ./bublik/bublik/settings.py
echo "✅ Docker environment setup complete!" 