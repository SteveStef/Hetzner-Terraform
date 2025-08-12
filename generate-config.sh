#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Reading config.json and generating configuration files...${NC}"

# Check if config.json exists
if [ ! -f "config.json" ]; then
    echo -e "${RED}❌ Error: config.json not found!${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ Error: jq is required but not installed.${NC}"
    echo -e "${YELLOW}💡 Install with: brew install jq (macOS) or apt install jq (Ubuntu)${NC}"
    exit 1
fi

# Check if files exist and warn user
if [ -f "terraform.tfvars" ] || [ -f "nginx.conf" ] || [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  Existing files found. They will be overwritten:${NC}"
    [ -f "terraform.tfvars" ] && echo -e "  - terraform.tfvars"
    [ -f "nginx.conf" ] && echo -e "  - nginx.conf"
    [ -f ".env" ] && echo -e "  - .env"
    echo -e "${YELLOW}📝 Recreating files...${NC}"
fi

echo -e "${BLUE}📖 Loading variables from config.json...${NC}"

# Load specific variables we need for terraform and nginx
HCLOUD_TOKEN=$(jq -r '.infrastructure.hcloud_token' config.json)
SSH_KEY_PATH=$(jq -r '.infrastructure.ssh_key_path' config.json)
MY_IP=$(jq -r '.infrastructure.my_ip' config.json)
SERVER_TYPE=$(jq -r '.infrastructure.server_type' config.json)
SERVER_LOCATION=$(jq -r '.infrastructure.server_location' config.json)
SERVER_NAME=$(jq -r '.infrastructure.server_name' config.json)
GITHUB_REPO=$(jq -r '.infrastructure.github_repo' config.json)
SSH_KEY_NAME=$(jq -r '.infrastructure.ssh_key_name' config.json)
FIREWALL_NAME=$(jq -r '.infrastructure.firewall_name' config.json)
USER_NAME=$(jq -r '.infrastructure.user_name' config.json)
IMAGE_TYPE=$(jq -r '.infrastructure.image_type' config.json)

# Application variables for nginx
DOMAIN=$(jq -r '.application.domain' config.json)
APP_PORT=$(jq -r '.application.app_port' config.json)
APP_NAME=$(jq -r '.application.app_name' config.json)

# Backup variables
BACKUP_ENABLED=$(jq -r '.backup.enabled' config.json)
MINIO_ENDPOINT=$(jq -r '.backup.minio_endpoint' config.json)
MINIO_ACCESS_KEY=$(jq -r '.backup.minio_access_key' config.json)
MINIO_SECRET_KEY=$(jq -r '.backup.minio_secret_key' config.json)
BACKUP_BUCKET=$(jq -r '.backup.backup_bucket' config.json)
RETENTION_COUNT=$(jq -r '.backup.retention_count' config.json)

# Database variables
DB_ENABLED=$(jq -r '.database.enabled' config.json)
DB_NAME=$(jq -r '.database.name' config.json)
DB_USER=$(jq -r '.database.user' config.json)
DB_PASSWORD=$(jq -r '.database.password' config.json)
DB_CONTAINER_NAME=$(jq -r '.database.container_name' config.json)

echo -e "${GREEN}✅ Variables loaded successfully${NC}"

# 1. Create terraform.tfvars with infrastructure variables in root
echo -e "${BLUE}📝 Creating terraform.tfvars...${NC}"

cat > terraform.tfvars << EOF
# Generated from config.json - DO NOT EDIT MANUALLY
# Generated on: $(date)

# Infrastructure Configuration
hcloud_token = "$HCLOUD_TOKEN"
ssh_key_path = "$SSH_KEY_PATH"
my_ip = "$MY_IP"
server_type = "$SERVER_TYPE"
server_location = "$SERVER_LOCATION"
server_name = "$SERVER_NAME"
github_repo = "$GITHUB_REPO"
ssh_key_name = "$SSH_KEY_NAME"
firewall_name = "$FIREWALL_NAME"
user_name = "$USER_NAME"
image_type = "$IMAGE_TYPE"

# Application Configuration
app_name = "$APP_NAME"
EOF

echo -e "${GREEN}✅ terraform.tfvars created${NC}"

# 2. Create nginx.conf with correct domain and port in root
echo -e "${BLUE}📝 Creating nginx.conf with domain: $DOMAIN and port: $APP_PORT...${NC}"

cat > nginx.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/ssl/mycerts/origin.pem;
    ssl_certificate_key /etc/ssl/mycerts/private.key;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

echo -e "${GREEN}✅ nginx.conf created${NC}"

# 3. Create main .env file in root directory (for docker-compose)
{
    echo "# Generated from config.json - DO NOT EDIT MANUALLY"
    echo "# Generated on: $(date)"
    echo "# Essential variables for docker-compose"
    echo ""
    
    # Extract only the essential variables for docker-compose
    echo "APP_NAME=$(jq -r '.application.app_name' config.json)"
    echo "APP_PORT=$(jq -r '.application.app_port' config.json)"
    echo "DOCKER_PORT=$(jq -r '.application.docker_port' config.json)"
    
} > .env

echo -e "${GREEN}✅ .env created (essential docker-compose variables only)${NC}"

# 4. Create backup script if backup is enabled
if [ "$BACKUP_ENABLED" = "true" ] && [ "$DB_ENABLED" = "true" ]; then
    echo -e "${BLUE}📝 Creating backup-script.sh...${NC}"
    
    cat > backup-script.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Configuration - Generated from config.json
MINIO_ALIAS="backup-server"
MINIO_ENDPOINT="MINIO_ENDPOINT_PLACEHOLDER"
ACCESS_KEY="MINIO_ACCESS_KEY_PLACEHOLDER"
SECRET_KEY="MINIO_SECRET_KEY_PLACEHOLDER"
BACKUP_BUCKET="BACKUP_BUCKET_PLACEHOLDER"

# Database configuration
DB_HOST="DB_CONTAINER_NAME_PLACEHOLDER"
DB_NAME="DB_NAME_PLACEHOLDER"
DB_USER="DB_USER_PLACEHOLDER"
DB_PASS="DB_PASSWORD_PLACEHOLDER"

# Backup settings
RETENTION_COUNT=RETENTION_COUNT_PLACEHOLDER
LOG_FILE="/var/log/database-backup.log"
BACKUP_DIR="/tmp"

# Generate backup filename
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="db_backup_${BACKUP_DATE}.sql.gz"
LOCAL_BACKUP="${BACKUP_DIR}/${BACKUP_FILE}"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    if [[ -f "$LOCAL_BACKUP" ]]; then
        rm -f "$LOCAL_BACKUP"
        log "Cleaned up temporary backup file"
    fi
}
trap cleanup EXIT

log "Starting database backup process"

# Check if MinIO client is installed
if ! command -v mc &> /dev/null; then
    log "ERROR: MinIO client (mc) is not installed"
    exit 1
fi

# Configure MinIO alias if not exists
if ! mc alias list | grep -q "^${MINIO_ALIAS}"; then
    log "Configuring MinIO alias: $MINIO_ALIAS"
    mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY" --insecure
fi

# Test MinIO connection
if ! mc ls "$MINIO_ALIAS" > /dev/null 2>&1; then
    log "ERROR: Cannot connect to MinIO server"
    exit 1
fi

# Create bucket if it doesn't exist
if ! mc ls "$MINIO_ALIAS/$BACKUP_BUCKET" > /dev/null 2>&1; then
    log "Creating backup bucket: $BACKUP_BUCKET"
    mc mb "$MINIO_ALIAS/$BACKUP_BUCKET"
fi

# Create database backup
log "Creating database backup for: $DB_NAME"
if ! docker exec "$DB_HOST" mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" | gzip > "$LOCAL_BACKUP"; then
    log "ERROR: Database backup failed"
    exit 1
fi

# Verify backup file
if [[ ! -s "$LOCAL_BACKUP" ]]; then
    log "ERROR: Backup file is empty or does not exist"
    exit 1
fi

BACKUP_SIZE=$(du -h "$LOCAL_BACKUP" | cut -f1)
log "Backup created successfully: $BACKUP_FILE (Size: $BACKUP_SIZE)"

# Upload to MinIO
log "Uploading backup to MinIO: $MINIO_ALIAS/$BACKUP_BUCKET/"
if ! mc cp "$LOCAL_BACKUP" "$MINIO_ALIAS/$BACKUP_BUCKET/"; then
    log "ERROR: Failed to upload backup to MinIO"
    exit 1
fi

log "Backup uploaded successfully: $BACKUP_FILE"

# Cleanup old backups (keep only latest specified count)
log "Cleaning up old backups (keeping only $RETENTION_COUNT most recent)"
BACKUP_COUNT=$(mc ls "$MINIO_ALIAS/$BACKUP_BUCKET/" | grep "db_backup_" | wc -l)

if [[ $BACKUP_COUNT -gt $RETENTION_COUNT ]]; then
    DELETE_COUNT=$((BACKUP_COUNT - RETENTION_COUNT))
    log "Found $BACKUP_COUNT backups, deleting $DELETE_COUNT oldest"
    
    mc ls "$MINIO_ALIAS/$BACKUP_BUCKET/" | grep "db_backup_" | head -n "$DELETE_COUNT" | while read -r line; do
        FILE_NAME=$(echo "$line" | awk '{print $NF}')
        if mc rm "$MINIO_ALIAS/$BACKUP_BUCKET/$FILE_NAME" 2>/dev/null; then
            log "Deleted old backup: $FILE_NAME"
        fi
    done
fi

# Backup summary
TOTAL_BACKUPS=$(mc ls "$MINIO_ALIAS/$BACKUP_BUCKET/" | grep "db_backup_" | wc -l)
log "Backup process completed successfully. Total backups: $TOTAL_BACKUPS"

exit 0
EOF

    # Replace placeholders with actual values
    sed -i "s|MINIO_ENDPOINT_PLACEHOLDER|$MINIO_ENDPOINT|g" backup-script.sh
    sed -i "s|MINIO_ACCESS_KEY_PLACEHOLDER|$MINIO_ACCESS_KEY|g" backup-script.sh
    sed -i "s|MINIO_SECRET_KEY_PLACEHOLDER|$MINIO_SECRET_KEY|g" backup-script.sh
    sed -i "s|BACKUP_BUCKET_PLACEHOLDER|$BACKUP_BUCKET|g" backup-script.sh
    sed -i "s|DB_CONTAINER_NAME_PLACEHOLDER|$DB_CONTAINER_NAME|g" backup-script.sh
    sed -i "s|DB_NAME_PLACEHOLDER|$DB_NAME|g" backup-script.sh
    sed -i "s|DB_USER_PLACEHOLDER|$DB_USER|g" backup-script.sh
    sed -i "s|DB_PASSWORD_PLACEHOLDER|$DB_PASSWORD|g" backup-script.sh
    sed -i "s|RETENTION_COUNT_PLACEHOLDER|$RETENTION_COUNT|g" backup-script.sh
    
    chmod +x backup-script.sh
    echo -e "${GREEN}✅ backup-script.sh created with config variables${NC}"

    # 5. Create systemd timer setup script
    echo -e "${BLUE}📝 Creating setup-backup-timer.sh...${NC}"
    
    cat > setup-backup-timer.sh << 'EOF'
#!/bin/bash
set -e

USER_NAME="$1"

# Create systemd backup service
cat > /etc/systemd/system/backup.service << "SYSTEMD_EOF"
[Unit]
Description=Database Backup Service
After=network.target

[Service]
Type=oneshot
User=USER_PLACEHOLDER
WorkingDirectory=/home/USER_PLACEHOLDER
ExecStart=/home/USER_PLACEHOLDER/backup-script.sh
StandardOutput=journal
StandardError=journal
SYSTEMD_EOF

# Replace placeholder with actual username
sed -i "s/USER_PLACEHOLDER/$USER_NAME/g" /etc/systemd/system/backup.service

# Create systemd backup timer
cat > /etc/systemd/system/backup.timer << "SYSTEMD_EOF"
[Unit]
Description=Run Database Backup daily at 2AM
Requires=backup.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
SYSTEMD_EOF

# Enable and start the timer
systemctl daemon-reload
systemctl enable backup.timer
systemctl start backup.timer

echo "Backup timer setup completed successfully"
EOF

    chmod +x setup-backup-timer.sh
    echo -e "${GREEN}✅ setup-backup-timer.sh created${NC}"

else
    echo -e "${YELLOW}⚠️  Backup disabled or database disabled - skipping backup script creation${NC}"
fi

# 6. Display summary
echo -e "${BLUE}📋 Configuration Summary:${NC}"
echo -e "  Server: $SERVER_NAME ($SERVER_TYPE in $SERVER_LOCATION)"
echo -e "  Domain: $DOMAIN"
echo -e "  App Port: $APP_PORT"
echo -e "  Repository: $GITHUB_REPO"
if [ "$BACKUP_ENABLED" = "true" ]; then
    echo -e "  Backup: Enabled (${RETENTION_COUNT} backups, daily at 2AM)"
    echo -e "  MinIO: $MINIO_ENDPOINT"
fi
if [ "$DB_ENABLED" = "true" ]; then
    echo -e "  Database: ${DB_CONTAINER_NAME} (${DB_NAME})"
fi

echo -e "${GREEN}🎉 All configuration files generated successfully!${NC}"
echo -e "${BLUE}📁 Files created/updated:${NC}"
echo -e "  - terraform.tfvars (infrastructure variables)"
echo -e "  - nginx.conf (domain: $DOMAIN, port: $APP_PORT)"
echo -e "  - .env (essential docker-compose variables)"
if [ "$BACKUP_ENABLED" = "true" ] && [ "$DB_ENABLED" = "true" ]; then
    echo -e "  - backup-script.sh (database backup with MinIO)"
    echo -e "  - setup-backup-timer.sh (systemd timer setup)"
fi

echo -e "${BLUE}🚀 Next steps:${NC}"
echo -e "  1. terraform apply (uses terraform.tfvars automatically)"
echo -e "  2. docker-compose up -d (uses .env automatically)"
if [ "$BACKUP_ENABLED" = "true" ]; then
    echo -e "  3. Backup system will be automatically configured and running daily at 2AM"
fi

# 7. Show preview of generated .env
echo -e "${YELLOW}📄 Preview of generated .env file:${NC}"
head -10 .env
