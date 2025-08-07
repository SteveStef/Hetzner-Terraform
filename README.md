# Terraform Deployment

Automated deployment of a Spring Boot cleaning business app using Terraform (Hetzner Cloud) and Docker Compose.

### Note you only need to edit the following:
1. `config.json` for all application properties
2. `docker-compose.yml` for environment variables and containers 
3. `origin.pem` and `private.key` with cloudflare credentials

## Quick Start

```bash
# 1. Configure settings
nvim config.json

# 2. Generate config files
./generate-config.sh

# 3. Deploy infrastructure
terraform init 
terraform plan
terraform apply
```

## File Structure

```
├── config.json              # Single source of truth
├── generate-config.sh       # Generates all config files
├── terraform.tfvars         # Generated: Infrastructure config
├── .env                     # Generated: Docker Compose variables
├── docker-compose.yml       # Container orchestration
├── main.tf                  # Infrastructure definition
└── certs/                   # SSL certificates from Cloudflare
```

## Key Variables (config.json)

### Critical (Must Be Correct)
- **`domain`**: Must match Cloudflare domain and SSL certificate
- **`docker_port`**: Must match Spring Boot `server.port`
- **`github_repo`**: Must be accessible repository URL

### Important (Affects Access)
- **`my_ip`**: Your IP for SSH access (update when IP changes)
- **`hcloud_token`**: Hetzner Cloud API token

### Server Config
- **`server_type`**: `cpx11` (€4.90/month) or `cpx21` (€9.90/month)
- **`server_location`**: `ash` (US East), `nbg1` (Germany), `hil` (US West)

## Common Issues

- **Can't SSH**: Check `my_ip` matches your current IP
- **App won't start**: Verify `docker_port` matches Spring Boot port
- **Domain not working**: Ensure `domain` matches Cloudflare exactly
- **Database connection**: Check logs with `docker-compose logs -f`

## Useful Commands

### Server Management
```bash
# SSH into server
ssh ubuntu@your-server-ip

# Restart server
sudo reboot

# Check server status
systemctl status nginx
systemctl status docker
```

### Docker Commands
```bash
# View running containers
docker ps

# View all containers
docker ps -a

# View container logs
docker logs web-app
docker logs mysql-db

# Follow logs live
docker logs -f web-app

# Restart containers
docker-compose down
docker-compose up -d

# Rebuild and restart
docker-compose up -d --build
```

### Database Commands
```bash
# Connect to MySQL container
docker exec -it mysql-db mysql -u root -p

# View database files
sudo ls -la /var/lib/docker/volumes/ubuntu_mysql_data/_data/

# Backup database
docker exec mysql-db mysqldump -u root -p default > backup.sql

# Check database connection from app
docker exec -it web-app ping mysql
```

### Cloud-Init Debugging
```bash
# Check cloud-init status
cloud-init status

# View cloud-init logs
cat /var/log/cloud-init-output.log
cat /var/log/cloud-init.log

# Search for errors
grep -i error /var/log/cloud-init-output.log
```

### NGINX Commands
```bash
# Test NGINX configuration
nginx -t

# Restart NGINX
systemctl restart nginx

# View NGINX logs
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log
```

## Security

- Never commit `terraform.tfvars` or `.env` to git
- Update `my_ip` when your IP changes
- Keep SSL certificates current in Cloudflare

## Server Instance Types

| Type | Price/Month | vCPU | RAM | SSD | Traffic | Best For |
|------|-------------|------|-----|-----|---------|----------|
| `cpx11` | €4.99 (~$5.40) | 2 | 2 GB | 40 GB | 1 TB | Small apps, testing |
| `cpx21` | €9.49 (~$10.30) | 3 | 4 GB | 80 GB | 2 TB | Production apps |
| `cpx31` | €16.49 (~$17.90) | 4 | 8 GB | 160 GB | 3 TB | High traffic apps |
| `cpx41` | €30.49 (~$33.10) | 8 | 16 GB | 240 GB | 4 TB | Enterprise apps |
| `cpx51` | €60.49 (~$65.70) | 16 | 32 GB | 360 GB | 5 TB | Large scale apps |

## US Server Locations

| Location Code | City | Region | Best For |
|---------------|------|--------|----------|
| `ash` | Ashburn, VA | US East | East Coast customers |
| `hil` | Hillsboro, OR | US West | West Coast customers |

## Image Types

| Image | Description | Use Case |
|-------|-------------|----------|
| `ubuntu-22.04` | Ubuntu 22.04 LTS | Recommended (default) |
| `ubuntu-20.04` | Ubuntu 20.04 LTS | Legacy support |
| `debian-11` | Debian 11 | Alternative to Ubuntu |
| `centos-stream-9` | CentOS Stream 9 | Enterprise environments |
| `fedora-39` | Fedora 39 | Latest features |
