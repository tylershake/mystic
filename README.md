# Mystic Home Server

A comprehensive self-hosted infrastructure setup using Docker Compose, featuring file storage, CI/CD, project management, and team collaboration tools.

## Overview

This project provides a complete home server stack with the following services:

- **Traefik** - Reverse proxy and SSL termination
- **Nextcloud** - File storage and collaboration platform
- **Jenkins** - Continuous integration and deployment
- **Confluence** - Team wiki and documentation
- **Jira** - Project and issue tracking
- **Bitbucket** - Git repository management
- **Mattermost** - Team chat and communication
- **PostgreSQL** - Database servers (4 instances)
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
| Confluence | 2002:2002 | confluence |
| Jira | 2001:2001 | jira |
| Bitbucket | 2003:2003 | bitbucket |
| Mattermost | 2000:2000 | mattermost |

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
| Traefik Dashboard | http://your-server:8080 | N/A |
| Nextcloud | http://cloud.mystic.home | mystic / password |
| Jenkins | http://jenkins.mystic.home | See initial setup |
| Confluence | http://confluence.mystic.home | Web setup required |
| Jira | http://jira.mystic.home | Web setup required |
| Bitbucket | http://bitbucket.mystic.home | Web setup required |
| Mattermost | http://chat.mystic.home | Web setup required |

## Project Structure

```
mystic_home_server/
├── .agents/                    # AI agent configurations
│   ├── developer-agent.md      # IaC and service configuration expert
│   ├── documentation-agent.md  # Documentation specialist
│   ├── bug-hunter-agent.md     # Debugging and troubleshooting expert
│   └── README.md              # Agent usage guide
├── docker-compose.yml          # Main service definitions
├── setup-volumes.sh           # Volume directory creation script
└── README.md                  # This file
```

## Data Storage

All persistent data is stored under `/data/docker/`:

```
/data/docker/
├── traefik/          # Traefik config and certificates
├── nextcloud/        # Nextcloud files and data
├── jenkins/          # Jenkins jobs and configuration
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
├── mariadbone/      # MariaDB data (Nextcloud)
├── postgresdbone/   # PostgreSQL data (Confluence)
├── postgresdbtwo/   # PostgreSQL data (Jira)
├── postgresdbthree/ # PostgreSQL data (Bitbucket)
└── postgresdbfour/  # PostgreSQL data (Mattermost)
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
192.168.1.100  cloud.mystic.home
192.168.1.100  jenkins.mystic.home
192.168.1.100  confluence.mystic.home
192.168.1.100  jira.mystic.home
192.168.1.100  bitbucket.mystic.home
192.168.1.100  chat.mystic.home
```

Replace `192.168.1.100` with your server's IP address.

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

### Database Connection Errors

**Note**: Confluence, Jira, and Bitbucket require manual database configuration during first-time setup:

- **Host**: `postgresdbone` (Confluence), `postgresdbtwo` (Jira), `postgresdbthree` (Bitbucket)
- **Database**: `home`
- **Username**: `mystic`
- **Password**: `password` (change this!)
- **Port**: `5432`

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
