#!/usr/bin/env bash

AUTO_CONFIRM=false
ARGS=()

for arg in "$@"; do
  case "$arg" in
  -y | --yes)
    AUTO_CONFIRM=true
    ;;
  *)
    ARGS+=("$arg")
    ;;
  esac
done

set -- "${ARGS[@]}"

get_container_name() {
  local service="$1"
  docker ps --format '{{.Names}}' | grep "${COMPOSE_PROJECT_NAME}-${service}"
}

# Check required environment variables
if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
  echo "❌ Required environment variables not set"
  echo "Required: DB_USER, DB_NAME"
  exit 1
fi

COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-bublik}
POSTGRES_CONTAINER=$(get_container_name "db")

create_backup() {
  local backup_dir="${1:-backups}"

  if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ Database container not found"
    echo "Make sure the database is running"
    exit 1
  fi

  mkdir -p "$backup_dir"

  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  DB_BACKUP_FILE="$backup_dir/db_backup_${TIMESTAMP}.sql"

  echo "📝 Creating database backup..."
  if docker exec $POSTGRES_CONTAINER pg_dump \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    >"$DB_BACKUP_FILE"; then
    echo "✅ Database backup created at: $DB_BACKUP_FILE"
    echo "📊 Backup size: $(du -h "$DB_BACKUP_FILE" | cut -f1)"
  else
    echo "❌ Failed to create database backup"
    rm -f "$DB_BACKUP_FILE"
    exit 1
  fi

  if $AUTO_CONFIRM; then
    compress_answer="y"
  else
    read -p "Compress the backup file? [y/N] " compress_answer
  fi

  if [[ $compress_answer =~ ^[Yy]$ ]]; then
    COMPRESSED_FILE="${DB_BACKUP_FILE}.gz"
    echo "📝 Compressing backup..."
    if gzip -c "$DB_BACKUP_FILE" >"$COMPRESSED_FILE"; then
      echo "✅ Compressed backup created at: $COMPRESSED_FILE"
      echo "📊 Compressed size: $(du -h "$COMPRESSED_FILE" | cut -f1)"
      if $AUTO_CONFIRM; then
        remove_answer="y"
      else
        read -p "Remove original uncompressed file? [y/N] " remove_answer
      fi
      if [[ $remove_answer =~ ^[Yy]$ ]]; then
        rm -f "$DB_BACKUP_FILE"
        echo "✅ Original file removed"
      fi
    else
      echo "❌ Failed to compress backup"
    fi
  fi
}

restore_backup() {
  local backup_file="$1"

  if [ -z "$POSTGRES_CONTAINER" ]; then
    echo "❌ Database container not found"
    echo "Make sure the database is running"
    exit 1
  fi

  if [ -z "$backup_file" ]; then
    echo "❌ No backup file specified"
    echo "Usage: $0 restore [-y] /path/to/backup.sql[.gz]"
    exit 1
  fi

  if [ ! -f "$backup_file" ]; then
    echo "❌ Backup file not found: $backup_file"
    exit 1
  fi

  echo "⚠️ This will overwrite the current database!"
  echo "📝 Restore from: $backup_file"

  if ! $AUTO_CONFIRM; then
    read -p "Continue? [y/N] " answer
    if [[ ! $answer =~ ^[Yy]$ ]]; then
      echo "⏭️ Restore cancelled"
      exit 0
    fi
  fi

  if [[ "$backup_file" == *.gz ]]; then
    echo "🔄 Restoring from compressed backup..."
    if gunzip -c "$backup_file" | docker exec -i $POSTGRES_CONTAINER psql \
      -U "$DB_USER" \
      -d "$DB_NAME"; then
      echo "✅ Database restored successfully"
    else
      echo "❌ Failed to restore database"
      exit 1
    fi
  else
    echo "🔄 Restoring database..."
    if cat "$backup_file" | docker exec -i $POSTGRES_CONTAINER psql \
      -U "$DB_USER" \
      -d "$DB_NAME"; then
      echo "✅ Database restored successfully"
    else
      echo "❌ Failed to restore database"
      exit 1
    fi
  fi
}

list_backups() {
  local backup_dir="${1:-backups}"

  if [ ! -d "$backup_dir" ]; then
    echo "❌ Backup directory not found: $backup_dir"
    exit 1
  fi

  echo "📝 Available database backups in $backup_dir:"
  echo "----------------------------------------"
  if ls -lh "$backup_dir"/db_backup_*.sql* 2>/dev/null; then
    echo "----------------------------------------"
  else
    echo "No database backups found"
  fi
}

# CLI
case "$1" in
"create")
  shift
  create_backup "${1:-backups}"
  ;;
"restore")
  shift
  restore_backup "$1"
  ;;
"list")
  shift
  list_backups "${1:-backups}"
  ;;
*)
  echo "Usage: $0 [-y|--yes] {create|restore|list} [path]"
  echo "  create [dir]     Create database backup (default dir: backups)"
  echo "  restore <file>   Restore database from backup file"
  echo "  list [dir]       List available backups (default dir: backups)"
  echo "  -y, --yes        Skip confirmation prompts"
  exit 1
  ;;
esac
