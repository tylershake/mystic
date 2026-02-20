# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Mystic** is a self-hosted home server infrastructure using Docker Compose. It defines ~17 containerized services (reverse proxy, file storage, CI/CD, wikis, issue tracking, chat, email, AI/LLM, and ELK logging) routed through a Traefik reverse proxy on a shared Docker network named `web`.

All persistent data lives under `${MYSTIC_ROOT}` (configured in `.env`, defaults to `.` — the project directory), with volume directories owned by specific UIDs/GIDs per service.

## Common Commands

```bash
# Initial setup (run once)
cp .env.example .env                            # Configure MYSTIC_ROOT if needed
docker network create web
sudo scripts/setup-volumes.sh                   # Create volume directories with correct ownership
sudo scripts/setup-volumes.sh --dry-run         # Preview what it would do

# Lifecycle
docker compose up -d                            # Start all services
docker compose down                             # Stop all services
docker compose ps                               # Check service status
docker compose logs -f [service]                # Tail logs for a specific service
docker compose restart [service]                # Restart a specific service
docker compose pull                             # Update all images

# Offline deployment (single command)
sudo scripts/deploy.sh                          # Full deployment on offline machine
sudo scripts/deploy.sh --dry-run                # Preview deployment steps

# Bundle for transfer (online machine)
sudo scripts/bundle.sh --all /mnt/usb/mystic                           # Bundle everything
sudo scripts/bundle.sh --services traefik,gateway,jenkins /mnt/usb/mystic  # Selective

# Individual offline scripts
scripts/save-images.sh /path/to/dest            # Export Docker images to files
scripts/save-images.sh --filter jenkins /path   # Export only matching images
sudo scripts/export-volumes.sh --all /path      # Archive all volume data
sudo scripts/export-volumes.sh --services jenkins,ollama /path  # Selective export
scripts/load-images.sh /path/to/images          # Import images on offline machine
sudo scripts/import-volumes.sh /path/to/volumes # Restore volumes on offline machine
```

## Architecture

### Networking

All services join an external Docker network called `web`. Traefik listens on port 80 and routes traffic to services based on Docker labels (`traefik.enable=true` + `traefik.http.routers.<name>.rule=Host(...)`). Traefik's own dashboard is exposed on port 8080 in insecure mode (no auth).

### Service Hostnames (`.mystic.home` domain)

| Hostname | Service |
|---|---|
| `home.mystic.home` | Nginx gateway/landing page |
| `cloud.mystic.home` | Nextcloud |
| `jenkins.mystic.home` | Jenkins CI |
| `bamboo.mystic.home` | Bamboo (Atlassian) |
| `confluence.mystic.home` | Confluence (Atlassian) |
| `jira.mystic.home` | Jira (Atlassian) |
| `bitbucket.mystic.home` | Bitbucket (Atlassian) |
| `chat.mystic.home` | Mattermost |
| `ai.mystic.home` | Open WebUI (Ollama frontend) |
| `kibana.mystic.home` | Kibana (ELK) |

### Databases

- **MariaDB** (`mariadbone:3306`): used by Nextcloud
- **PostgreSQL** (5 separate instances, `postgresdbone` through `postgresdbfive`):
  - `postgresdbone` → Confluence
  - `postgresdbtwo` → Jira
  - `postgresdbthree` → Bitbucket
  - `postgresdbfour` → Mattermost
  - `postgresdbfive` → Bamboo

### Non-Traefik Ports

Some services expose ports directly (not through Traefik):

| Port | Service | Protocol |
|---|---|---|
| 8080 | Traefik dashboard | HTTP |
| 50000 | Jenkins agents | JNLP |
| 54663 | Bamboo remote agents | TCP |
| 8091 | Confluence collaborative editing | TCP |
| 7999 | Bitbucket SSH | SSH |
| 25, 587, 143 | Mail server | SMTP/IMAP |
| 5044, 5010 | Logstash | Beats/TCP |
| 11434 | Ollama API | HTTP (internal) |

### ELK Stack

Logstash listens on ports 5044 (Beats) and 5010 (TCP/JSON), parses logs, and forwards to Elasticsearch at `http://elasticsearch:9200`. Kibana also reads from Elasticsearch. Log indices are created daily. Config is at `config/logstash/pipeline/logstash.conf`.

### AI Stack

Ollama runs the local LLM inference engine (GPU passthrough enabled via `deploy.resources`). Open WebUI connects to Ollama at `http://ollama:11434` and is the user-facing interface at `ai.mystic.home`.

## Volume Ownership (Critical)

`setup-volumes.sh` must be run before `docker compose up` to create directories with the correct UID:GID. Key mappings:

| UID:GID | Services |
|---|---|
| 0:0 | Traefik, Ollama, Open WebUI |
| 33:33 | Nextcloud |
| 101:101 | Nginx |
| 999:999 | MariaDB, all PostgreSQL instances |
| 1000:1000 | Jenkins, ELK stack |
| 2000:2000 | Mattermost |
| 2001:2001 | Jira |
| 2002:2002 | Confluence |
| 2003:2003 | Bitbucket |
| 2005:2005 | Bamboo |
| 5000:5000 | Mail server |

## Key Files

- `docker-compose.yml` — all service definitions, labels, volumes, environment variables
- `.env.example` — environment configuration template (MYSTIC_ROOT for portable paths)
- `config/traefik.toml` — Traefik reverse proxy config (Docker provider, entrypoints, debug logging)
- `config/logstash/pipeline/logstash.conf` — Logstash input/filter/output pipeline
- `scripts/setup-volumes.sh` — creates host directories with correct ownership (requires `sudo`)
- `scripts/save-images.sh` / `scripts/load-images.sh` — offline image transfer
- `scripts/export-volumes.sh` / `scripts/import-volumes.sh` — offline volume backup/restore
- `scripts/deploy.sh` — single-command offline deployment with preflight checks
- `scripts/bundle.sh` — selective service bundling for offline transfer

## Default Credentials

The default username is `mystic` and password is `password` across services (marked as TODO in the compose file — these should be changed before production use).
