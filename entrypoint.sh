#!/bin/sh
set -eu

: "${WORKFLOW_NAME:?WORKFLOW_NAME env var required (e.g. notion-backup)}"
: "${N8N_ENCRYPTION_KEY:?N8N_ENCRYPTION_KEY env var required}"

CREDS=${CREDENTIALS_FILE:-/secrets/credentials.json}
if [ -f "$CREDS" ]; then
  n8n import:credentials --input="$CREDS"
fi

exec n8n execute --file=/workflows/"${WORKFLOW_NAME}".json
