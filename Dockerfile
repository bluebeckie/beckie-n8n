# n8n image for Cloud Run Jobs.
# Build: docker build -t beckie-n8n .
# Run:   docker run --rm --env-file .env \
#          -e WORKFLOW_NAME=notion-backup \
#          -v "$PWD/credentials.json:/secrets/credentials.json:ro" \
#          beckie-n8n
FROM docker.n8n.io/n8nio/n8n:latest

ENV GENERIC_TIMEZONE=Asia/Taipei \
    TZ=Asia/Taipei \
    N8N_BLOCK_ENV_ACCESS_IN_NODE=false \
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
    NODE_FUNCTION_ALLOW_BUILTIN=process \
    N8N_RUNNERS_ENABLED=true

USER root
RUN mkdir -p /workflows && chown node:node /workflows
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
USER node

COPY --chown=node:node AI-WatchTower/AI-Watch-Tower.json                /workflows/ai-watchtower.json
COPY --chown=node:node Notion-Backup/Notion-Backup-gDrive-Git-Line.json /workflows/notion-backup.json
COPY --chown=node:node Error-Notification.json                          /workflows/error-notification.json

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
