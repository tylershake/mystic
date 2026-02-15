# Mystic Home Server

A comprehensive self-hosted infrastructure setup using Docker Compose, featuring file storage, CI/CD, project management, and team collaboration tools.

## Overview

This project provides a complete home server stack with the following services:

- **Traefik** - Reverse proxy and SSL termination
- **Nginx Gateway** - Landing page with links to all services
- **Nextcloud** - File storage and collaboration platform
- **Jenkins** - Continuous integration and deployment
- **Bamboo** - Build and deployment server
- **Confluence** - Team wiki and documentation
- **Jira** - Project and issue tracking
- **Bitbucket** - Git repository management
- **Mattermost** - Team chat and communication
- **Mail Server** - Full-featured SMTP/IMAP email service
- **PostgreSQL** - Database servers (5 instances)
- **MariaDB** - MySQL-compatible database

All services are accessible via `*.mystic.home` domain names through Traefik.

## Prerequisites

- **Operating System**: Ubuntu/Debian Linux (tested on Ubuntu 22.04+)
- **Docker**: Version 20.10 or later
- **Docker Compose**: Version 2.0 or later
- **Disk Space**: Minimum 50GB recommended for `/data/docker`
- **Memory**: Minimum 16GB RAM recommended
- **Root Access**: Required for initial setup

### Install Docker

```bash
# Update package index
sudo apt update

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group (optional, for non-root access)
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose-plugin
```

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/mystic_home_server.git
cd mystic_home_server
```

### 2. Prepare Volume Directories

**IMPORTANT**: Docker containers run as specific users (UIDs). You must create directories with the correct ownership.

```bash
# Make the setup script executable
chmod +x setup-volumes.sh

# Preview what will be created (dry run)
./setup-volumes.sh --dry-run

# Create directories with proper permissions (requires root)
sudo ./setup-volumes.sh

# Verify ownership (should show numeric UIDs like 999, 2000, 2001, etc.)
ls -lan /data/docker/
```

#### Container UIDs Reference

| Service | UID:GID | User |
|---------|---------|------|
| PostgreSQL (all instances) | 999:999 | postgres |
| MariaDB | 999:999 | mysql |
| Nextcloud | 33:33 | www-data |
| Jenkins | 1000:1000 | jenkins |
| Bamboo | 2005:2005 | bamboo |
| Confluence | 2002:2002 | confluence |
| Jira | 2001:2001 | jira |
| Bitbucket | 2003:2003 | bitbucket |
| Mattermost | 2000:2000 | mattermost |
| Mail Server | 5000:5000 | mailserver |
| Gateway (Nginx) | 101:101 | nginx |

### 3. Create Docker Network

```bash
# Create the external network that all services will use
docker network create web
```

### 4. Configure Services (Optional)

Before starting, you may want to:

- **Change default passwords** in `docker-compose.yml` (currently all set to `password`)
- **Configure Traefik** - Create `/data/docker/traefik/traefik.toml`
- **Set up DNS** - Configure `*.mystic.home` to point to your server IP

### 5. Start Services

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# Check service status
docker compose ps
```

### 6. Access Services

Once running, services are available at:

| Service | URL | Default Admin |
|---------|-----|---------------|
| Gateway | http://home.mystic.home | N/A |
| Traefik Dashboard | http://your-server:8080 | N/A |
| Nextcloud | http://cloud.mystic.home | mystic / password |
| Jenkins | http://jenkins.mystic.home | See initial setup |
| Bamboo | http://bamboo.mystic.home | Web setup required |
| Confluence | http://confluence.mystic.home | Web setup required |
| Jira | http://jira.mystic.home | Web setup required |
| Bitbucket | http://bitbucket.mystic.home | Web setup required |
| Mattermost | http://chat.mystic.home | Web setup required |
| Mail Server | SMTP/IMAP (see [Mail Server Configuration](#mail-server-configuration)) | CLI setup required |

## Project Structure

```
mystic_home_server/
├── .agents/                    # AI agent configurations
│   ├── developer-agent.md      # IaC and service configuration expert
│   ├── documentation-agent.md  # Documentation specialist
│   ├── bug-hunter-agent.md     # Debugging and troubleshooting expert
│   └── README.md              # Agent usage guide
├── config/                     # Configuration files
│   └── traefik.toml            # Traefik configuration
├── docker-compose.yml          # Main service definitions
├── setup-volumes.sh           # Volume directory creation script
└── README.md                  # This file
```

## Data Storage

All persistent data is stored under `/data/docker/`:

```
/data/docker/
├── traefik/          # Traefik config and certificates
├── gateway/          # Gateway landing page
│   ├── html/         # Static website files (from separate repo)
│   └── nginx.conf    # Custom nginx configuration (optional)
├── nextcloud/        # Nextcloud files and data
├── jenkins/          # Jenkins jobs and configuration
├── bamboo/           # Bamboo build plans and artifacts
├── confluence/       # Confluence pages and attachments
├── jira/            # Jira issues and projects
├── bitbucket/       # Git repositories
├── mattermost/      # Chat messages and uploads
│   ├── config/
│   ├── data/
│   ├── logs/
│   ├── plugins/
│   ├── clientplugins/
│   └── bleveindexes/
├── mailserver/      # Mail server data
│   ├── mail-data/   # Mailboxes and messages
│   ├── mail-state/  # Server state
│   ├── mail-logs/   # Mail logs
│   └── config/      # Mail server configuration
├── mariadbone/      # MariaDB data (Nextcloud)
├── postgresdbone/   # PostgreSQL data (Confluence)
├── postgresdbtwo/   # PostgreSQL data (Jira)
├── postgresdbthree/ # PostgreSQL data (Bitbucket)
├── postgresdbfour/  # PostgreSQL data (Mattermost)
└── postgresdbfive/  # PostgreSQL data (Bamboo)
```

## Management Commands

### View Service Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f nextcloud

# Last 100 lines
docker compose logs --tail=100 nextcloud
```

### Restart Services

```bash
# Restart all services
docker compose restart

# Restart specific service
docker compose restart nextcloud
```

### Update Services

```bash
# Pull latest images
docker compose pull

# Recreate containers with new images
docker compose up -d

# Remove old images
docker image prune
```

### Stop Services

```bash
# Stop all services
docker compose down

# Stop and remove volumes (WARNING: deletes all data!)
docker compose down -v
```

### Backup Data

```bash
# Stop services first
docker compose down

# Backup all data
sudo tar -czf mystic-backup-$(date +%Y%m%d).tar.gz /data/docker/

# Restart services
docker compose up -d
```

## Configuration

### Traefik Configuration

Create `/data/docker/traefik/traefik.toml`:

```toml
[global]
  checkNewVersion = true
  sendAnonymousUsage = false

[api]
  dashboard = true
  insecure = true

[entryPoints]
  [entryPoints.web]
    address = ":80"

  [entryPoints.websecure]
    address = ":443"

[providers]
  [providers.docker]
    endpoint = "unix:///var/run/docker.sock"
    exposedByDefault = false
```

### DNS Configuration

Add these entries to your local DNS server or `/etc/hosts`:

```
192.168.1.100  home.mystic.home
192.168.1.100  mystic.home
192.168.1.100  cloud.mystic.home
192.168.1.100  jenkins.mystic.home
192.168.1.100  bamboo.mystic.home
192.168.1.100  confluence.mystic.home
192.168.1.100  jira.mystic.home
192.168.1.100  bitbucket.mystic.home
192.168.1.100  chat.mystic.home
192.168.1.100  mail.mystic.home
```

Replace `192.168.1.100` with your server's IP address.

### Mail Server Configuration

The mail server uses [docker-mailserver](https://docker-mailserver.github.io/docker-mailserver/latest/) and runs independently from Traefik on dedicated mail ports.

#### First-Time Setup

> **Note**: The mail server takes a minute or two to fully initialize on first start. Watch the logs with `docker compose logs -f mailserver` and wait until you see `is up and running` before running setup commands. Running them too early will fail.

```bash
# Create your first email account
docker exec -it mailserver setup email add user@mystic.home yourpassword

# List email accounts
docker exec -it mailserver setup email list

# Generate DKIM keys for email authentication
docker exec -it mailserver setup config dkim
```

#### DNS Records

For the mail server to work properly, configure these DNS records:

| Type | Name | Value |
|------|------|-------|
| MX | mystic.home | mail.mystic.home (priority 10) |
| A | mail.mystic.home | your-server-ip |
| TXT | mystic.home | v=spf1 mx ~all |
| TXT | _dmarc.mystic.home | v=DMARC1; p=quarantine |
| TXT | mail._domainkey.mystic.home | (generated by DKIM setup above) |

#### Email Client Settings

| Protocol | Server | Port | Security |
|----------|--------|------|----------|
| IMAP | mail.mystic.home | 143 | None (plaintext) |
| SMTP (sending) | mail.mystic.home | 587 | None (plaintext) |

> **Recommended client**: Use [Thunderbird](https://www.thunderbird.net/) for plaintext (non-SSL) connections. Outlook may refuse to connect without encryption even when configured to allow it.

> **When SSL is enabled**, switch your client to the encrypted ports: IMAP on 993 (SSL/TLS), SMTP on 465 (SSL/TLS), and POP3 on 995 (SSL/TLS). These ports are commented out in `docker-compose.yml` until SSL is configured.

#### SSL Certificates

SSL is **disabled by default** (`SSL_TYPE=` empty) so the mail server can start cleanly for testing without certificates. To enable SSL for production:

1. Set `SSL_TYPE` in `docker-compose.yml` (e.g., `SSL_TYPE=letsencrypt` or `SSL_TYPE=manual`).
2. Mount your certificate files into the container (see [docker-mailserver SSL docs](https://docker-mailserver.github.io/docker-mailserver/latest/config/security/ssl/)).
3. Uncomment the encrypted ports (465, 993, 995) in the `ports` section of `docker-compose.yml`.
4. Restart the mail server: `docker compose restart mailserver`.

#### Enabled Features

- **SpamAssassin** — spam filtering
- **ClamAV** — **disabled by default** (`ENABLE_CLAMAV=0`). Uses ~1GB RAM and can cause OOM crashes on memory-constrained hosts. Set to `1` in `docker-compose.yml` to enable.
- **Fail2Ban** — **disabled by default** (`ENABLE_FAIL2BAN=0`). Conflicts with the container's `no-new-privileges` security setting. Set to `1` and add `cap_add: NET_ADMIN` to enable.

#### Useful Commands

```bash
# Check mail server status
docker exec -it mailserver setup debug show-mail-users

# View mail logs
docker logs mailserver --tail 50

# Add email alias
docker exec -it mailserver setup alias add alias@mystic.home user@mystic.home

# Restart after config changes
docker compose restart mailserver
```

### Jenkins Plugin Installation

Jenkins requires plugins for most functionality (Git integration, pipelines, credentials management, etc.). Since this server may run in an offline (air-gapped) environment, there are two approaches to installing plugins.

#### Approach 1: Online-to-Offline Migration (Recommended)

Set up Jenkins on a machine with internet access first, install all desired plugins through the UI, then transfer the entire volume to your offline server.

1. **Start Jenkins with internet access** and complete initial setup at `http://jenkins.mystic.home`.
2. **Install plugins** via **Manage Jenkins > Plugins > Available plugins**. Common picks:

   | Plugin | Purpose |
   |--------|---------|
   | Git | Git SCM integration |
   | Pipeline | Jenkinsfile-based pipelines |
   | Blue Ocean | Modern pipeline UI |
   | Credentials Binding | Inject secrets into builds |
   | Docker Pipeline | Build inside Docker containers |
   | SSH Agent | SSH key authentication in builds |

3. **Verify** all plugins load without errors (**Manage Jenkins > Plugins > Installed plugins**).
4. **Stop Jenkins and copy the volume** to your offline server:

```bash
# On the online machine — archive the Jenkins volume
docker compose stop jenkins
sudo tar -czf jenkins-volume.tar.gz /data/docker/jenkins/

# Transfer to offline server (USB drive, scp, etc.)
scp jenkins-volume.tar.gz user@offline-server:/tmp/

# On the offline server — restore
docker compose stop jenkins
sudo tar -xzf /tmp/jenkins-volume.tar.gz -C /
sudo chown -R 1000:1000 /data/docker/jenkins/
docker compose start jenkins
```

#### Approach 2: Manual Plugin Installation

Download individual plugin files and place them directly into the plugins directory. This is useful when you only need a few specific plugins.

1. **Download `.hpi`/`.jpi` files** from the Jenkins Plugin Index on a machine with internet access:

   ```
   https://updates.jenkins.io/download/plugins/<plugin-name>/
   ```

2. **Resolve dependencies** — each plugin page lists its required dependencies. Download those as well. Missing dependencies will cause Jenkins to fail to load the plugin.

3. **Copy plugin files** into the Jenkins plugins directory:

```bash
# Copy downloaded plugins to the volume
sudo cp *.hpi /data/docker/jenkins/plugins/
sudo chown 1000:1000 /data/docker/jenkins/plugins/*.hpi

# Restart Jenkins to load new plugins
docker compose restart jenkins

# Verify plugins loaded
docker compose logs jenkins | grep -i "plugin"
```

> **Note**: Manual installation can be tedious for plugins with deep dependency trees (e.g., Pipeline requires 20+ transitive dependencies). Approach 1 avoids this problem entirely.

## Security Considerations

### Critical Security Tasks

Before using in production:

1. **Change All Passwords** - The default password `password` is used everywhere
2. **Secure Traefik Dashboard** - Add authentication or disable public access
3. **Enable HTTPS** - Configure SSL/TLS certificates (Let's Encrypt recommended)
4. **Network Isolation** - Consider running services on isolated networks
5. **Firewall Rules** - Restrict access to necessary ports only
6. **Regular Backups** - Implement automated backup strategy
7. **Update Images** - Regularly update container images for security patches

### Password Management

Update passwords in `docker-compose.yml`:

```yaml
environment:
  - MYSQL_PASSWORD=<strong-password-here>
  - MYSQL_ROOT_PASSWORD=<strong-password-here>
  - POSTGRES_PASSWORD=<strong-password-here>
  - NEXTCLOUD_ADMIN_PASSWORD=<strong-password-here>
```

Consider using Docker secrets or environment variable files for better security.

## Troubleshooting

### Containers Won't Start

```bash
# Check container logs
docker compose logs <service-name>

# Common issues:
# 1. Network doesn't exist: docker network create web
# 2. Wrong permissions: sudo ./setup-volumes.sh
# 3. Port conflicts: Check if ports 80, 443 are available
```

### Permission Denied Errors

```bash
# Verify directory ownership
ls -lan /data/docker/

# Fix PostgreSQL permissions
sudo chown -R 999:999 /data/docker/postgres*

# Fix MariaDB permissions
sudo chown -R 999:999 /data/docker/mariadbone
```

### Service Not Accessible

```bash
# Check if Traefik is running
docker compose ps traefik

# Verify Traefik routes
docker compose logs traefik | grep -i route

# Check network
docker network inspect web
```

### PostgreSQL Version Compatibility

Atlassian products (Confluence, Jira, Bitbucket, Bamboo) only support specific PostgreSQL versions. Before changing the `postgres` image tag in `docker-compose.yml`, check the compatibility matrix for each service:

- [Confluence supported platforms](https://confluence.atlassian.com/doc/supported-platforms-702702702.html)
- [Jira supported platforms](https://confluence.atlassian.com/adminjiraserver/supported-platforms-702702700.html)
- [Bitbucket supported platforms](https://confluence.atlassian.com/bitbucketserver/supported-platforms-702702702.html)
- [Bamboo supported platforms](https://confluence.atlassian.com/bamboo/supported-platforms-702702702.html)

Using an unsupported version (e.g., too new or too old) can cause connection failures, schema errors, or silent data issues during setup. If you hit database errors during first-time setup, check the version compatibility first.

Also note: changing PostgreSQL major versions on existing data requires a migration — you can't just swap the image tag. Wipe the data directory or use `pg_upgrade` if switching versions.

### Database Connection Errors

**Note**: Confluence, Jira, Bitbucket, and Bamboo require manual database configuration during first-time setup:

- **Host**: `postgresdbone` (Confluence), `postgresdbtwo` (Jira), `postgresdbthree` (Bitbucket), `postgresdbfive` (Bamboo)
- **Database**: `home`
- **Username**: `mystic`
- **Password**: `password` (change this!)
- **Port**: `5432`
- **JDBC URL format**: `jdbc:postgresql://<host>:5432/home`

## AI Agents

This project includes specialized AI agent configurations to assist with:

- **Developer Agent** - Infrastructure as Code and service configuration
- **Documentation Agent** - Creating and maintaining documentation
- **Bug Hunter Agent** - Debugging and troubleshooting issues

See [`.agents/README.md`](.agents/README.md) for usage instructions.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review service logs: `docker compose logs <service>`
3. Consult the AI agents (see `.agents/` directory)
4. Check official documentation for each service

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Docker](https://www.docker.com/)
- Powered by [Traefik](https://traefik.io/)
- All service trademarks belong to their respective owners

---

**Important**: This configuration is for home/development use. Additional hardening is required for production deployments.
