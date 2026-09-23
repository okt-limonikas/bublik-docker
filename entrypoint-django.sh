#!/bin/bash

source /app/bublik/entrypoint-common.sh

setup_umask

echo "Setting up required directories..."
ANALYTICS_DB_DIR="$(dirname "${ANALYTICS_DB_PATH:-/app/bublik/analytics/analytics.sqlite3}")"
AI_CHAT_FILES_DIR="${AI_CHAT_FILE_STORAGE_DIR:-/app/bublik/ai-chat-files}"
LOGS_S3_CACHE_DIR="${LOGS_S3_CACHE_DIR:-/app/bublik/logs-s3-cache}"
ensure_directory "${BUBLIK_LOGDIR}"
ensure_directory "/app/bublik/logs"
ensure_directory "${ANALYTICS_DB_DIR}"
ensure_directory "${AI_CHAT_FILES_DIR}"
ensure_directory "${LOGS_S3_CACHE_DIR}"
ensure_directory "${BUBLIK_DOCKER_DATA_DIR}/django-logs"
ensure_directory "${BUBLIK_DOCKER_DATA_DIR}/te-logs/logs"
ensure_directory "${BUBLIK_DOCKER_DATA_DIR}/te-logs/incoming"
ensure_directory "${BUBLIK_DOCKER_DATA_DIR}/te-logs/bad"

setup_permissions "${BUBLIK_LOGDIR}" "${BUBLIK_DOCKER_DATA_DIR}/django-logs" "/app/bublik/logs"

echo "Collect Static Files"
python manage.py collectstatic --noinput

echo "Apply Database Migrations"
python manage.py migrate

ANALYTICS_ENABLED_NORMALIZED=$(echo "${ANALYTICS_ENABLED:-0}" | tr '[:upper:]' '[:lower:]')
if [ "$ANALYTICS_ENABLED_NORMALIZED" = "1" ] || [ "$ANALYTICS_ENABLED_NORMALIZED" = "true" ] || [ "$ANALYTICS_ENABLED_NORMALIZED" = "yes" ]; then
  echo "Apply Analytics Database Migrations"
  python manage.py migrate --database=analytics
fi

echo "Initialize configs"
python manage.py initialize_configs

echo "Creating Superuser"
python manage.py shell << EOF
from django.contrib.auth import get_user_model
User = get_user_model()
SUPERUSER_EMAIL = '${DJANGO_SUPERUSER_EMAIL:-admin@bublik.com}'
SUPERUSER_PASSWORD = '${DJANGO_SUPERUSER_PASSWORD:-admin}'
if not User.objects.filter(email=SUPERUSER_EMAIL).exists():
    User.objects.create_superuser(
        email=SUPERUSER_EMAIL,
        password=SUPERUSER_PASSWORD,
    )
    print(f'Superuser created with email: {SUPERUSER_EMAIL}')
else:
    print(f'Superuser with email {SUPERUSER_EMAIL} already exists.')
EOF

setup_runtime_permissions "${ANALYTICS_DB_DIR}"
setup_private_directory "${AI_CHAT_FILES_DIR}"
# The S3 log cache is a bind mount too, so it arrives root-owned; only django
# writes to it.
setup_private_directory "${LOGS_S3_CACHE_DIR}"

exec_as_user "$@" 
