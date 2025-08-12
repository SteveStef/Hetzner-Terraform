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
BACKUP_SCHEDULE=$(jq -r '.backup.schedule' config.json)

# Database variables
DB_ENABLED=$(jq -r '.database.enabled' config.json)
DB_NAME=$(jq -r '.database.name' config.json)
DB_USER=$(jq -r '.database.user' config.json)
DB_PASSWORD=$(jq -r '.database.password' config.json)
DB_CONTAINER_NAME=$(jq -r '.database.container_name' config.json)

echo -e "${GREEN}✅ Variables loaded successfully${NC}"

# Function to convert schedule names to systemd OnCalendar format
convert_schedule() {
    local schedule="$1"
    case "$schedule" in
        "daily_2am"|"daily_2AM")
            echo "*-*-* 02:00:00"
            ;;
        "daily_midnight")
            echo "*-*-* 00:00:00"
            ;;
        "daily_6am")
            echo "*-*-* 06:00:00"
            ;;
        "daily_noon")
            echo "*-*-* 12:00:00"
            ;;
        "twice_daily")
            echo "*-*-* 02:00:00,14:00:00"
            ;;
        "weekly_sunday")
            echo "Sun *-*-* 02:00:00"
            ;;
        "weekly_monday")
            echo "Mon *-*-* 02:00:00"
            ;;
        "hourly")
            echo "*-*-* *:00:00"
            ;;
        *)
            echo "*-*-* 02:00:00"  # Default fallback
            echo "Warning: Unknown schedule '$schedule', using default daily_2am" >&2
            ;;
    esac
}

# Convert the schedule
if [[ "$BACKUP_ENABLED" == "true" ]]; then
    SYSTEMD_SCHEDULE=$(convert_schedule "$BACKUP_SCHEDULE")
    echo -e "${GREEN}📅 Backup schedule: $BACKUP_SCHEDULE → $SYSTEMD_SCHEDULE${NC}"
fi

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

# Backup Configuration
backup_enabled = $BACKUP_ENABLED
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
    
    # Add database variables if database is enabled
    if [ "$DB_ENABLED" = "true" ]; then
        echo ""
        echo "# Database variables"
        echo "DB_NAME=$(jq -r '.database.name' config.json)"
        echo "DB_PASSWORD=$(jq -r '.database.password' config.json)"
        echo "DB_CONTAINER_NAME=$(jq -r '.database.container_name' config.json)"
    fi
    
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
LOG_FILE="USER_NAME_LOG_PLACEHOLDER"
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
    sed -i "s|DB_USER_PLACEHOLDER|root|g" backup-script.sh
    sed -i "s|DB_PASSWORD_PLACEHOLDER|$DB_PASSWORD|g" backup-script.sh
    sed -i "s|RETENTION_COUNT_PLACEHOLDER|$RETENTION_COUNT|g" backup-script.sh
    sed -i "s|USER_NAME_LOG_PLACEHOLDER|/home/$USER_NAME/database-backup.log|g" backup-script.sh
    
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
Description=Run Database Backup (SCHEDULE_PLACEHOLDER)
Requires=backup.service

[Timer]
OnCalendar=SYSTEMD_SCHEDULE_PLACEHOLDER
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
SYSTEMD_EOF

# Replace placeholders with actual values
sed -i "s|SCHEDULE_PLACEHOLDER|$BACKUP_SCHEDULE|g" /etc/systemd/system/backup.timer
sed -i "s|SYSTEMD_SCHEDULE_PLACEHOLDER|$SYSTEMD_SCHEDULE|g" /etc/systemd/system/backup.timer

# Enable and start the timer
systemctl daemon-reload
systemctl enable backup.timer
systemctl start backup.timer

echo "Backup timer setup completed successfully"
EOF

    chmod +x setup-backup-timer.sh
    
    # Replace placeholders in the generated script
    sed -i "s|SCHEDULE_PLACEHOLDER|$BACKUP_SCHEDULE|g" setup-backup-timer.sh
    sed -i "s|SYSTEMD_SCHEDULE_PLACEHOLDER|$SYSTEMD_SCHEDULE|g" setup-backup-timer.sh
    
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
    echo -e "  Backup: Enabled (${RETENTION_COUNT} backups, $BACKUP_SCHEDULE)"
    echo -e "  MinIO: $MINIO_ENDPOINT"
fi
if [ "$DB_ENABLED" = "true" ]; then
    echo -e "  Database: ${DB_CONTAINER_NAME} (${DB_NAME})"
fi

# 6. Create health check script
echo -e "${BLUE}📝 Creating health-check.sh...${NC}"

cat > health-check.sh << 'HEALTH_EOF'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 System Health Check${NC}"
echo -e "${BLUE}===================${NC}"

# Function to check status and print result
check_status() {
    local service=$1
    local command=$2
    local description=$3
    
    echo -n "[$service] $description... "
    
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✅ OK${NC}"
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        return 1
    fi
}

# Function to check status with custom success condition
check_status_custom() {
    local service=$1
    local command=$2
    local description=$3
    local success_condition=$4
    
    echo -n "[$service] $description... "
    
    local result=$(eval "$command" 2>/dev/null)
    if [[ $result == *"$success_condition"* ]]; then
        echo -e "${GREEN}✅ OK${NC}"
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        return 1
    fi
}

# Initialize counters
total_checks=0
failed_checks=0

# Cloud-init status
total_checks=$((total_checks + 1))
check_status_custom "CLOUD-INIT" "sudo cloud-init status" "Cloud-init completion" "done" || failed_checks=$((failed_checks + 1))

# Docker service
total_checks=$((total_checks + 1))
check_status "DOCKER" "sudo systemctl is-active docker" "Docker service" || failed_checks=$((failed_checks + 1))

# App container
total_checks=$((total_checks + 1))
check_status "CONTAINER" "docker ps --filter 'name=APP_NAME_PLACEHOLDER' --filter 'status=running' | grep -q APP_NAME_PLACEHOLDER" "App container running" || failed_checks=$((failed_checks + 1))

# Database container (conditional)
DB_ENABLED_PLACEHOLDER

# Nginx service
total_checks=$((total_checks + 1))
check_status "NGINX" "sudo systemctl is-active nginx" "Nginx service" || failed_checks=$((failed_checks + 1))

# Nginx configuration
total_checks=$((total_checks + 1))
check_status "NGINX" "sudo nginx -t" "Nginx configuration" || failed_checks=$((failed_checks + 1))

# App health (HTTP response)
total_checks=$((total_checks + 1))
check_status "WEB" "curl -f -s http://localhost >/dev/null" "Web app responding" || failed_checks=$((failed_checks + 1))

# Database connectivity (conditional)
DB_CONNECTIVITY_PLACEHOLDER

# Backup timer (conditional)
BACKUP_TIMER_PLACEHOLDER

# Disk space (warn if >80% full)
total_checks=$((total_checks + 1))
disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $disk_usage -lt 80 ]]; then
    echo -e "[SYSTEM] Disk space (${disk_usage}% used)... ${GREEN}✅ OK${NC}"
else
    echo -e "[SYSTEM] Disk space (${disk_usage}% used)... ${YELLOW}⚠️  WARNING${NC}"
    failed_checks=$((failed_checks + 1))
fi

# Memory usage (warn if >90% full)
total_checks=$((total_checks + 1))
memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
if [[ $memory_usage -lt 90 ]]; then
    echo -e "[SYSTEM] Memory usage (${memory_usage}% used)... ${GREEN}✅ OK${NC}"
else
    echo -e "[SYSTEM] Memory usage (${memory_usage}% used)... ${YELLOW}⚠️  WARNING${NC}"
    failed_checks=$((failed_checks + 1))
fi

echo -e "\n${BLUE}Summary:${NC}"
passed_checks=$((total_checks - failed_checks))

if [[ $failed_checks -eq 0 ]]; then
    echo -e "${GREEN}🎉 All systems operational! ($passed_checks/$total_checks checks passed)${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Issues detected: $failed_checks/$total_checks checks failed${NC}"
    echo -e "${YELLOW}💡 Check individual service logs for details${NC}"
    exit 1
fi
HEALTH_EOF

# Replace placeholders with conditional checks
sed -i "s|APP_NAME_PLACEHOLDER|$APP_NAME|g" health-check.sh

# Add database checks conditionally
if [ "$DB_ENABLED" = "true" ]; then
    # Create temporary files with the replacement content
    cat > /tmp/db_container_check << EOF
total_checks=\$((total_checks + 1))
check_status "CONTAINER" "docker ps --filter 'name=$DB_CONTAINER_NAME' --filter 'status=running' | grep -q $DB_CONTAINER_NAME" "Database container running" || failed_checks=\$((failed_checks + 1))
EOF

    cat > /tmp/db_connectivity_check << EOF
total_checks=\$((total_checks + 1))
check_status "DATABASE" "docker exec $DB_CONTAINER_NAME mysqladmin ping -u root -p\\\${DB_PASSWORD} --silent" "Database connectivity" || failed_checks=\$((failed_checks + 1))
EOF

    # Replace placeholders using awk
    awk '/DB_ENABLED_PLACEHOLDER/ {system("cat /tmp/db_container_check"); next} {print}' health-check.sh > /tmp/health-check-temp1
    awk '/DB_CONNECTIVITY_PLACEHOLDER/ {system("cat /tmp/db_connectivity_check"); next} {print}' /tmp/health-check-temp1 > /tmp/health-check-temp2
    mv /tmp/health-check-temp2 health-check.sh
    
    # Cleanup
    rm -f /tmp/db_container_check /tmp/db_connectivity_check /tmp/health-check-temp1
else
    # Remove database placeholders
    sed -i '/DB_ENABLED_PLACEHOLDER/d' health-check.sh
    sed -i '/DB_CONNECTIVITY_PLACEHOLDER/d' health-check.sh
fi

# Add backup checks conditionally
if [ "$BACKUP_ENABLED" = "true" ] && [ "$DB_ENABLED" = "true" ]; then
    cat > /tmp/backup_check << EOF
total_checks=\$((total_checks + 1))
check_status "BACKUP" "sudo systemctl is-active backup.timer" "Backup timer active" || failed_checks=\$((failed_checks + 1))

# MinIO connectivity check
total_checks=\$((total_checks + 1))
check_status "MINIO" "mc ls backup-server/$BACKUP_BUCKET >/dev/null 2>&1" "MinIO connectivity" || failed_checks=\$((failed_checks + 1))
EOF

    awk '/BACKUP_TIMER_PLACEHOLDER/ {system("cat /tmp/backup_check"); next} {print}' health-check.sh > /tmp/health-check-temp
    mv /tmp/health-check-temp health-check.sh
    rm -f /tmp/backup_check
else
    sed -i '/BACKUP_TIMER_PLACEHOLDER/d' health-check.sh
fi

chmod +x health-check.sh
echo -e "${GREEN}✅ health-check.sh created with conditional checks${NC}"

# 7. Create backup restore script if backup is enabled
if [ "$BACKUP_ENABLED" = "true" ] && [ "$DB_ENABLED" = "true" ]; then
    echo -e "${BLUE}📝 Creating restore-backup.sh...${NC}"
    
    cat > restore-backup.sh << 'RESTORE_EOF'
#!/bin/bash
set -euo pipefail

# Configuration - Generated from config.json
MINIO_ALIAS="backup-server"
MINIO_ENDPOINT="MINIO_ENDPOINT_PLACEHOLDER"
ACCESS_KEY="MINIO_ACCESS_KEY_PLACEHOLDER"
SECRET_KEY="MINIO_SECRET_KEY_PLACEHOLDER"
BACKUP_BUCKET="BACKUP_BUCKET_PLACEHOLDER"

# Database configuration
DB_CONTAINER_NAME="DB_CONTAINER_NAME_PLACEHOLDER"
DB_NAME="DB_NAME_PLACEHOLDER"
DB_USER="root"
DB_PASS="DB_PASSWORD_PLACEHOLDER"

# Restore settings
RESTORE_DIR="/tmp"
LOG_FILE="USER_NAME_LOG_PLACEHOLDER"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp]${NC} $message"
    echo "$timestamp - $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    local message="$1"
    log "${RED}ERROR: $message${NC}"
    exit 1
}

# Check if running as root (for docker commands)
if [[ $EUID -eq 0 ]]; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi

echo -e "${BLUE}🔄 Database Backup Restore Process${NC}"
echo -e "${BLUE}=================================${NC}"

log "Starting database backup restore process"

# Step 1: Configure MinIO alias
log "Configuring MinIO alias: $MINIO_ALIAS"
mc alias set "$MINIO_ALIAS" "$MINIO_ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY" >/dev/null 2>&1 || error_exit "Failed to configure MinIO alias"

# Step 2: Find the most recent backup
log "Finding most recent backup from MinIO bucket: $BACKUP_BUCKET"
LATEST_BACKUP=$(mc ls "$MINIO_ALIAS/$BACKUP_BUCKET/" | grep "db_backup_" | sort -k6,7 | tail -1 | awk '{print $NF}')

if [[ -z "$LATEST_BACKUP" ]]; then
    error_exit "No backup files found in bucket $BACKUP_BUCKET"
fi

log "Found latest backup: $LATEST_BACKUP"

# Step 3: Download the backup
BACKUP_FILE="$RESTORE_DIR/$LATEST_BACKUP"
log "Downloading backup to: $BACKUP_FILE"
mc cp "$MINIO_ALIAS/$BACKUP_BUCKET/$LATEST_BACKUP" "$BACKUP_FILE" || error_exit "Failed to download backup file"

# Step 4: Verify backup file
if [[ ! -f "$BACKUP_FILE" ]]; then
    error_exit "Backup file not found after download: $BACKUP_FILE"
fi

log "Backup file size: $(du -h "$BACKUP_FILE" | cut -f1)"

# Step 5: Check if database container is running
if ! $DOCKER_CMD ps | grep -q "$DB_CONTAINER_NAME"; then
    error_exit "Database container '$DB_CONTAINER_NAME' is not running"
fi

# Step 6: Create a backup of current database before restore
CURRENT_BACKUP="$RESTORE_DIR/pre_restore_backup_$(date +%Y%m%d_%H%M%S).sql"
log "Creating backup of current database before restore: $CURRENT_BACKUP"
$DOCKER_CMD exec "$DB_CONTAINER_NAME" mysqldump -u "$DB_USER" -p"$DB_PASS" --single-transaction --routines --triggers "$DB_NAME" > "$CURRENT_BACKUP" || error_exit "Failed to create current database backup"

# Step 7: Decompress and restore the backup
log "Restoring database from backup: $LATEST_BACKUP"

# Check if file is compressed
if [[ "$BACKUP_FILE" == *.gz ]]; then
    log "Decompressing and restoring compressed backup"
    gunzip -c "$BACKUP_FILE" | $DOCKER_CMD exec -i "$DB_CONTAINER_NAME" mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" || error_exit "Failed to restore compressed backup"
else
    log "Restoring uncompressed backup"
    $DOCKER_CMD exec -i "$DB_CONTAINER_NAME" mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$BACKUP_FILE" || error_exit "Failed to restore backup"
fi

# Step 8: Verify restore
log "Verifying database restore"
TABLE_COUNT=$($DOCKER_CMD exec "$DB_CONTAINER_NAME" mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SHOW TABLES;" | wc -l)
if [[ $TABLE_COUNT -gt 1 ]]; then
    log "${GREEN}✅ Database restore completed successfully${NC}"
    log "Database contains $((TABLE_COUNT - 1)) tables"
else
    error_exit "Database restore may have failed - no tables found"
fi

# Step 9: Cleanup
log "Cleaning up temporary files"
rm -f "$BACKUP_FILE"

# Step 10: Show restore summary
echo -e "\n${GREEN}🎉 Backup Restore Summary${NC}"
echo -e "${GREEN}=========================${NC}"
echo -e "✅ Restored from: ${YELLOW}$LATEST_BACKUP${NC}"
echo -e "✅ Database: ${YELLOW}$DB_NAME${NC}"
echo -e "✅ Tables restored: ${YELLOW}$((TABLE_COUNT - 1))${NC}"
echo -e "✅ Pre-restore backup: ${YELLOW}$CURRENT_BACKUP${NC}"
echo -e "\n${BLUE}💡 Important Notes:${NC}"
echo -e "- Your previous database was backed up to: $CURRENT_BACKUP"
echo -e "- You may want to restart your application containers:"
echo -e "  ${YELLOW}docker-compose restart${NC}"
echo -e "- Check application logs after restart:"
echo -e "  ${YELLOW}docker logs app${NC}"

log "Database restore process completed successfully"
RESTORE_EOF

    # Replace placeholders with actual values
    sed -i "s|MINIO_ENDPOINT_PLACEHOLDER|$MINIO_ENDPOINT|g" restore-backup.sh
    sed -i "s|MINIO_ACCESS_KEY_PLACEHOLDER|$MINIO_ACCESS_KEY|g" restore-backup.sh
    sed -i "s|MINIO_SECRET_KEY_PLACEHOLDER|$MINIO_SECRET_KEY|g" restore-backup.sh
    sed -i "s|BACKUP_BUCKET_PLACEHOLDER|$BACKUP_BUCKET|g" restore-backup.sh
    sed -i "s|DB_CONTAINER_NAME_PLACEHOLDER|$DB_CONTAINER_NAME|g" restore-backup.sh
    sed -i "s|DB_NAME_PLACEHOLDER|$DB_NAME|g" restore-backup.sh
    sed -i "s|DB_PASSWORD_PLACEHOLDER|$DB_PASSWORD|g" restore-backup.sh
    sed -i "s|USER_NAME_LOG_PLACEHOLDER|/home/$USER_NAME/restore-backup.log|g" restore-backup.sh
    
    chmod +x restore-backup.sh
    echo -e "${GREEN}✅ restore-backup.sh created with MinIO configuration${NC}"
fi

echo -e "${GREEN}🎉 All configuration files generated successfully!${NC}"
echo -e "${BLUE}📁 Files created/updated:${NC}"
echo -e "  - terraform.tfvars (infrastructure variables)"
echo -e "  - nginx.conf (domain: $DOMAIN, port: $APP_PORT)"
echo -e "  - .env (essential docker-compose variables)"
echo -e "  - health-check.sh (system monitoring script)"
if [ "$BACKUP_ENABLED" = "true" ] && [ "$DB_ENABLED" = "true" ]; then
    echo -e "  - backup-script.sh (database backup with MinIO)"
    echo -e "  - setup-backup-timer.sh (systemd timer setup)"
fi

echo -e "${BLUE}🚀 Next steps:${NC}"
echo -e "  1. terraform apply (uses terraform.tfvars automatically)"
echo -e "  2. docker-compose up -d (uses .env automatically)"
if [ "$BACKUP_ENABLED" = "true" ]; then
    echo -e "  3. Backup system will be automatically configured and running $BACKUP_SCHEDULE"
fi

# 7. Show preview of generated .env
echo -e "${YELLOW}📄 Preview of generated .env file:${NC}"
head -10 .env
