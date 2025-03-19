#!/bin/bash
if [ -f "bublik/settings.py" ]; then
  echo "⚠️  Removing existing settings.py..."
  rm bublik/settings.py
fi
echo "📝 Copying docker settings template..."
cp docker-settings.py.template ./bublik/bublik/settings.py