#!/bin/bash
# Upload a TE log tarball (te_logs.tar from Test Environment's publish_logs)
# to Bublik, which stores it under the project's S3 upload base and imports it.
#
# Usage: upload_logs.sh <file.tar> [project-id]
# Environment:
#   BUBLIK_TOKEN  personal access token of an admin (Settings -> Access tokens)
#   BUBLIK_URL    Bublik base URL (default: http://localhost${URL_PREFIX})

set -euo pipefail

file="${1:-}"
project="${2:-}"

if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo "Usage: $0 <file.tar> [project-id]" >&2
    exit 1
fi
if [[ -z "${BUBLIK_TOKEN:-}" ]]; then
    echo "Set BUBLIK_TOKEN to an admin's personal access token (bpat_...)" >&2
    exit 1
fi

url="${BUBLIK_URL:-http://localhost${URL_PREFIX:-}}"
args=(-sS --fail-with-body -H "Authorization: Bearer ${BUBLIK_TOKEN}" -F "file=@${file}")
[[ -n "${project}" ]] && args+=(-F "project=${project}")

curl "${args[@]}" "${url%/}/api/v2/importruns/upload/"
echo
