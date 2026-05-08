# beckie-n8n

n8n workflows that run on a schedule. Edited locally, deployed as Cloud Run Jobs.

## Architecture

```
┌──────────────────────────┐                       ┌──────────────────────────┐
│ Local Docker             │                       │ This repo (git)          │
│  - n8n editor :5678      │  export:workflow ──▶  │  - <name>.json           │
│  - SQLite (creds + WFs)  │  export:credentials   │  - credentials.json (.gi)│
└──────────────────────────┘                       │  - Dockerfile            │
                                                   │  - entrypoint.sh         │
                                                   └─────────────┬────────────┘
                                                                 │ deploy.sh
                                                                 ▼
                                          ┌────────────────────────────────────┐
                                          │ GCP Artifact Registry              │
                                          │  beckie-n8n image (workflows baked)│
                                          └─────────────────┬──────────────────┘
                                                            │
                          ┌─────────────────────────────────┼─────────────────────────────────┐
                          ▼                                 ▼                                 ▼
              ┌──────────────────────┐          ┌──────────────────────┐          ┌──────────────────────┐
              │ Cloud Run Job        │          │ Cloud Run Job        │          │ Cloud Run Job        │
              │  ai-watchtower       │          │  notion-backup       │          │  security-weekly     │
              │  WORKFLOW_NAME=...   │          │  WORKFLOW_NAME=...   │          │  WORKFLOW_NAME=...   │
              └──────────┬───────────┘          └──────────┬───────────┘          └──────────┬───────────┘
                         │ triggered by                    │                                 │
                         └──────────────────────┬──────────┴─────────────────────────────────┘
                                                ▼
                          ┌──────────────────────────────────────────┐
                          │ Cloud Scheduler                          │
                          │  one cron entry per Job                  │
                          └──────────────────────────────────────────┘

                          ┌──────────────────────────────────────────┐
                          │ Secret Manager (mounted into each Job)   │
                          │  - n8n-encryption-key  → env var         │
                          │  - n8n-credentials-json → /secrets/...   │
                          │  - n8n-line-testuser, n8n-line-audience  │
                          └──────────────────────────────────────────┘
```

Local Docker is the **editor** (with SQLite holding workflows +
credentials). Git is the **source of truth for shipped state** —
workflow JSONs and an encrypted credentials export live here.
Cloud Run Jobs are stateless: each run starts a fresh container,
imports credentials from Secret Manager, executes one workflow,
exits. Cloud Scheduler triggers them on a cron.

## Local setup (editing workflows)

Edit happens in the local n8n UI. Each meaningful change is then
exported to JSON and committed.

### One-time

```sh
docker volume create n8n_data
cp .env.example .env   # then fill in TESTUSER, AUDIENCE, N8N_ENCRYPTION_KEY
```

To get the encryption key from an already-running n8n:

```sh
docker exec n8n cat /home/node/.n8n/config
```

### Start the editor

Use the `startn8ndocker` alias (preferred — matches what's been in
use), or:

```sh
docker compose up -d
```

Then open http://localhost:5678.

### Edit-and-commit loop

1. Edit a workflow in the n8n UI. Test it (`Execute Workflow`).
2. Find its workflow ID — visible in the URL while editing
   (`/workflow/<id>`) or via `docker exec n8n n8n list:workflow`.
3. Export back to the same JSON path the deploy expects:

   ```sh
   # AI-WatchTower
   docker exec n8n n8n export:workflow \
     --id=<id> --output=/tmp/wf.json
   docker cp n8n:/tmp/wf.json AI-WatchTower/AI-Watch-Tower.json

   # Notion-Backup
   docker exec n8n n8n export:workflow \
     --id=<id> --output=/tmp/wf.json
   docker cp n8n:/tmp/wf.json Notion-Backup/Notion-Backup-gDrive-Git-Line.json

   # Error notification
   docker exec n8n n8n export:workflow \
     --id=<id> --output=/tmp/wf.json
   docker cp n8n:/tmp/wf.json Error-Notification.json
   ```

4. `git add <path> && git commit && git push`. Cloud Run picks up
   the new image on next deploy.

### When credentials change locally

Re-export the encrypted bundle and refresh Secret Manager:

```sh
docker exec n8n n8n export:credentials --all --output=/tmp/c.json
docker cp n8n:/tmp/c.json credentials.json
docker exec n8n rm /tmp/c.json

# then re-upload to Secret Manager (deploy script in Phase 2 will
# wrap this; until then, manual:)
gcloud secrets versions add n8n-credentials-json \
  --project=upbeat-stratum-315909 \
  --data-file=credentials.json
```

The encryption key lives in `.env` (locally) and Secret Manager
(cloud). Don't change it — if you do, every existing encrypted
credential becomes unrecoverable.

## GCP setup (scheduled execution)

> **Status: not yet implemented.** This section describes the
> planned shape. The `deploy.sh` referenced below will be added in
> a follow-up commit.

GCP project: `upbeat-stratum-315909`, region `asia-east1`.

### One-time setup

1. **Enable APIs**

   ```sh
   gcloud services enable run.googleapis.com \
     cloudscheduler.googleapis.com \
     artifactregistry.googleapis.com \
     secretmanager.googleapis.com \
     --project=upbeat-stratum-315909
   ```

2. **Create Artifact Registry repo**

   ```sh
   gcloud artifacts repositories create beckie-n8n \
     --repository-format=docker \
     --location=asia-east1 \
     --project=upbeat-stratum-315909
   ```

3. **Push secrets**

   ```sh
   gcloud secrets create n8n-encryption-key \
     --data-file=<(grep N8N_ENCRYPTION_KEY .env | cut -d= -f2-)
   gcloud secrets create n8n-credentials-json --data-file=credentials.json
   gcloud secrets create n8n-line-testuser \
     --data-file=<(grep ^TESTUSER= .env | cut -d= -f2-)
   gcloud secrets create n8n-line-audience \
     --data-file=<(grep ^AUDIENCE= .env | cut -d= -f2-)
   ```

4. **Service account** with `roles/secretmanager.secretAccessor`
   and `roles/run.invoker`. Used by both the Jobs (to read
   secrets) and Cloud Scheduler (to invoke the Jobs).

### Deploy

```sh
./deploy.sh           # builds, pushes, redeploys all three Jobs
./deploy.sh notion-backup   # just one
```

The script:
- builds the image
- pushes to Artifact Registry
- creates/updates one Cloud Run Job per workflow, each pinned to
  its `WORKFLOW_NAME` env var, with the secrets bound

### Schedule

Cron schedules live in Cloud Scheduler, one entry per Job:

| Workflow         | Cron (Asia/Taipei) | Purpose                  |
| ---------------- | ------------------ | ------------------------ |
| ai-watchtower    | TBD                | AI news daily summary    |
| notion-backup    | TBD                | Notion → Drive + GitHub  |
| security-weekly  | TBD (deferred)     | Security news weekly     |

Cloud Scheduler invokes the Job via the Cloud Run Admin API. The
service account from the one-time setup needs `roles/run.invoker`.

### Trigger a Job manually

For testing without waiting for cron:

```sh
gcloud run jobs execute notion-backup \
  --region=asia-east1 --project=upbeat-stratum-315909
```

## Repo layout

```
.
├── AI-WatchTower/         workflow project
├── Notion-Backup/         workflow project
├── Security-Weekly/       workflow project (no JSON yet)
├── Error-Notification.json   shared error handler
├── Dockerfile             Cloud Run image
├── entrypoint.sh          imports creds, runs workflow by name
├── docker-compose.yml     local editor
├── .env.example           local config template
├── _plan/                 plan + tasks (gitignored)
├── _logs/                 per-session decision log (gitignored)
├── credentials.json       encrypted creds export (gitignored)
└── .env                   local secrets (gitignored)
```

## Files NOT in deployment

- `RAG_Chatbot_for_Company_Documents_using_Google_Drive_and_Gemini.json`
  is an interactive chat workflow (not schedule-triggered) and
  stays on the local editor only.
