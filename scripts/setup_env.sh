#!/bin/bash
if [ ! -f ".env" ]; then
  echo "📝 Creating .env from template..."
  cp .env.example .env
  echo "✅ Created .env file"
else
  echo "⏭️ Using existing .env file"
  echo "ℹ️  To reset to defaults, remove .env and run setup again"
fi