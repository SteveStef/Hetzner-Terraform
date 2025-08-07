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

# 4. Display summary
echo -e "${BLUE}📋 Configuration Summary:${NC}"
echo -e "  Server: $SERVER_NAME ($SERVER_TYPE in $SERVER_LOCATION)"
echo -e "  Domain: $DOMAIN"
echo -e "  App Port: $APP_PORT"
echo -e "  Repository: $GITHUB_REPO"

echo -e "${GREEN}🎉 All configuration files generated successfully!${NC}"
echo -e "${BLUE}📁 Files created/updated:${NC}"
echo -e "  - terraform.tfvars (infrastructure variables)"
echo -e "  - nginx.conf (domain: $DOMAIN, port: $APP_PORT)"
echo -e "  - .env (essential docker-compose variables: APP_NAME, APP_PORT, DOCKER_PORT)"

echo -e "${BLUE}🚀 Next steps:${NC}"
echo -e "  1. terraform apply (uses terraform.tfvars automatically)"
echo -e "  2. docker-compose up -d (uses .env automatically)"

# 5. Show preview of generated .env
echo -e "${YELLOW}📄 Preview of generated .env file:${NC}"
head -10 .env
