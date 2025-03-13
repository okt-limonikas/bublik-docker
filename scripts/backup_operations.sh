#!/bin/bash

# Check required environment variables
if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ] || [ -z "$BUBLIK_DOCKER_DATA_DIR" ]; then
  echo "❌ Required environment variables not set"
  echo "Required: DB_USER, DB_NAME, BUBLIK_DOCKER_DATA_DIR"
  exit 1
fi

create_backup() {
  local backup_dir="${1:-backups}"

  # Ensure backup directory exists
  mkdir -p "$backup_dir"

  # Generate backup filename with timestamp
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  BACKUP_DIR_NAME="bublik_backup_${TIMESTAMP}"
  FINAL_BACKUP_FILE="$backup_dir/${BACKUP_DIR_NAME}.tar.gz"

  # Create temporary directory for the backup
  TMP_DIR=$(mktemp -d)
  BACKUP_TMP_DIR="$TMP_DIR/$BACKUP_DIR_NAME"
  mkdir -p "$BACKUP_TMP_DIR"/{db,logs}

  echo "📦 Creating complete backup..."

  # Backup database
  echo "📝 Creating database backup..."
  if docker exec postgres pg_dump \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    > "$BACKUP_TMP_DIR/db/database.sql"; then
    echo "✅ Database backup created"
  else
    echo "❌ Failed to create database backup"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  # Backup TE logs
  echo "📝 Creating TE logs backup..."
  if docker cp te-log-server:/home/te-logs/logs/. "$BACKUP_TMP_DIR/logs/"; then
    echo "✅ TE logs backup created"
  else
    echo "❌ Failed to copy logs from container"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  # Create final archive
  echo "📝 Creating backup archive..."
  if tar -czf "$FINAL_BACKUP_FILE" -C "$TMP_DIR" "$BACKUP_DIR_NAME"; then
    echo "✅ Backup archive created successfully at: $FINAL_BACKUP_FILE"
    echo "📊 Backup size: $(du -h "$FINAL_BACKUP_FILE" | cut -f1)"
  else
    echo "❌ Failed to create backup archive"
    rm -f "$FINAL_BACKUP_FILE"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  # Cleanup
  rm -rf "$TMP_DIR"
}

restore_backup() {
  local backup_file="$1"

  if [ -z "$backup_file" ]; then
    echo "❌ No backup file specified"
    echo "Usage: $0 restore /path/to/backup.tar.gz"
    exit 1
  fi

  if [ ! -f "$backup_file" ]; then
    echo "❌ Backup file not found: $backup_file"
    exit 1
  fi

  echo "⚠️ This will overwrite both the current database and TE logs!"
  echo "📝 Restore from: $backup_file"
  read -p "Continue? [y/N] " answer
  if [[ ! $answer =~ ^[Yy]$ ]]; then
    echo "⏭️ Restore cancelled"
    exit 0
  fi

  # Create temporary directory for extraction
  TMP_DIR=$(mktemp -d)

  echo "🔄 Extracting backup archive..."
  if tar -xzf "$backup_file" -C "$TMP_DIR"; then
    BACKUP_DIR=$(find "$TMP_DIR" -maxdepth 1 -type d -name "bublik_backup_*")

    if [ -z "$BACKUP_DIR" ]; then
      echo "❌ Invalid backup archive structure"
      rm -rf "$TMP_DIR"
      exit 1
    fi

    # Restore database
    echo "🔄 Restoring database..."
    if [ -f "$BACKUP_DIR/db/database.sql" ]; then
      if cat "$BACKUP_DIR/db/database.sql" | docker exec -i postgres psql \
        -U "$DB_USER" \
        -d "$DB_NAME"; then
        echo "✅ Database restored successfully"
      else
        echo "❌ Failed to restore database"
        rm -rf "$TMP_DIR"
        exit 1
      fi
    else
      echo "❌ Database backup not found in archive"
      rm -rf "$TMP_DIR"
      exit 1
    fi

    # Restore TE logs
    echo "🔄 Restoring TE logs..."
    if [ -d "$BACKUP_DIR/logs" ]; then
      if docker cp "$BACKUP_DIR/logs/." te-log-server:/home/te-logs/logs/; then
        echo "🔧 Fixing permissions..."
        # Get host user's UID/GID from environment
        HOST_UID=$(id -u)
        HOST_GID=$(id -g)
        
        # Set ownership and permissions inside container
        docker exec te-log-server chown -R ${HOST_UID}:${HOST_GID} /home/te-logs/logs/
        docker exec te-log-server chmod -R 2775 /home/te-logs/logs/
        
        # Set permissions on host side as well
        if [ "$EUID" -ne 0 ]; then
          sudo chown -R ${HOST_UID}:${HOST_GID} "${BUBLIK_DOCKER_DATA_DIR}/te-logs/logs"
          sudo chmod -R 2775 "${BUBLIK_DOCKER_DATA_DIR}/te-logs/logs"
        else
          chown -R ${HOST_UID}:${HOST_GID} "${BUBLIK_DOCKER_DATA_DIR}/te-logs/logs"
          chmod -R 2775 "${BUBLIK_DOCKER_DATA_DIR}/te-logs/logs"
        fi
        
        echo "✅ TE logs restored successfully with correct permissions"
      else
        echo "❌ Failed to restore TE logs"
        rm -rf "$TMP_DIR"
        exit 1
      fi
    else
      echo "❌ TE logs not found in archive"
      rm -rf "$TMP_DIR"
      exit 1
    fi

    echo "✅ Complete backup restored successfully!"
  else
    echo "❌ Failed to extract backup archive"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  # Cleanup
  rm -rf "$TMP_DIR"
}

list_backups() {
  local backup_dir="${1:-backups}"

  if [ ! -d "$backup_dir" ]; then
    echo "❌ Backup directory not found: $backup_dir"
    exit 1
  fi

  echo "📝 Available backups in $backup_dir:"
  echo "----------------------------------------"
  if ls -lh "$backup_dir"/*.tar.gz 2>/dev/null; then
    echo "----------------------------------------"
  else
    echo "No backups found"
  fi
}

# Command line interface
case "$1" in
  "create")
    create_backup "${2:-backups}"
    ;;
  "restore")
    restore_backup "$2"
    ;;
  "list")
    list_backups "${2:-backups}"
    ;;
  *)
    echo "Usage: $0 {create|restore|list} [path]"
    echo "  create [dir]     Create complete backup (default dir: backups)"
    echo "  restore <file>   Restore complete backup from archive"
    echo "  list [dir]       List available backups (default dir: backups)"
    exit 1
    ;;
esac 