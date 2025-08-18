terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

# Check if backup files exist when backup is enabled
locals {
  backup_script_exists = var.backup_enabled ? fileexists("${path.module}/build/backup-script.sh") : true
  setup_script_exists = var.backup_enabled ? fileexists("${path.module}/build/setup-backup-timer.sh") : true
}

# Validation for backup files
check "backup_files_validation" {
  assert {
    condition = local.backup_script_exists
    error_message = "build/backup-script.sh not found. Run './generate-config.sh' first to generate backup scripts."
  }
  
  assert {
    condition = local.setup_script_exists
    error_message = "build/setup-backup-timer.sh not found. Run './generate-config.sh' first to generate backup scripts."
  }
}

# Provider
provider "hcloud" {
  token = var.hcloud_token
}

# SSH Key
resource "hcloud_ssh_key" "default" {
  name       = var.ssh_key_name
  public_key = file(var.ssh_key_path)
}

# Firewall
resource "hcloud_firewall" "web_firewall" {
  name = var.firewall_name

  rule {
    direction = "in"
    port      = "22"
    protocol  = "tcp"
    source_ips = [var.my_ip]
  }

  rule {
    direction = "in"
    port      = "80"
    protocol  = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    port      = "443"
    protocol  = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Server
resource "hcloud_server" "node1" {
  name        = var.server_name
  image       = var.image_type
  server_type = var.server_type
  location    = var.server_location
  ssh_keys    = [hcloud_ssh_key.default.id]

  user_data = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - nginx
      - docker.io
      - git
      - curl

    users:
      - name: ${var.user_name}
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash

    write_files:
      - path: /etc/ssl/mycerts/origin.pem
        content: ${base64encode(file("${path.module}/certs/origin.pem"))}
        encoding: b64
        permissions: '0644'

      - path: /etc/ssl/mycerts/private.key
        content: ${base64encode(file("${path.module}/certs/private.key"))}
        encoding: b64
        permissions: '0600'

      - path: /etc/nginx/conf.d/default.conf
        content: ${base64encode(file("${path.module}/build/nginx.conf"))}
        encoding: b64
        permissions: '0644'

      - path: /home/${var.user_name}/docker-compose.yml
        content: ${base64encode(file("${path.module}/docker-compose.yml"))}
        encoding: b64
        permissions: '0644'

      - path: /home/${var.user_name}/.env
        content: ${base64encode(file("${path.module}/build/.env"))}
        encoding: b64
        permissions: '0644'

      - path: /home/${var.user_name}/health-check.sh
        content: ${base64encode(file("${path.module}/build/health-check.sh"))}
        encoding: b64
        permissions: '0755'

      - path: /home/${var.user_name}/redeploy-app.sh
        content: ${base64encode(file("${path.module}/build/redeploy-app.sh"))}
        encoding: b64
        permissions: '0755'
%{ if var.backup_enabled }
      - path: /home/${var.user_name}/backup-script.sh
        content: ${base64encode(file("${path.module}/build/backup-script.sh"))}
        encoding: b64
        permissions: '0755'

      - path: /home/${var.user_name}/setup-backup-timer.sh
        content: ${base64encode(file("${path.module}/build/setup-backup-timer.sh"))}
        encoding: b64
        permissions: '0755'

      - path: /home/${var.user_name}/restore-backup.sh
        content: ${base64encode(file("${path.module}/build/restore-backup.sh"))}
        encoding: b64
        permissions: '0755'
%{ endif }

    runcmd:
      - mkdir -p /etc/ssl/mycerts
      - systemctl start docker
      - systemctl enable docker
      - usermod -aG docker ${var.user_name}
      - curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      - chmod +x /usr/local/bin/docker-compose
      - ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
      - cd /home/${var.user_name}
      - git clone ${var.github_repo} ${var.app_name}
      - chown -R ${var.user_name}:${var.user_name} /home/${var.user_name}
      - docker-compose up -d
      - nginx -t
      - systemctl restart nginx
      - systemctl enable nginx
%{ if var.backup_enabled }
      - curl -o /tmp/cloudflare-origin-ca.pem https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem
      - cp /tmp/cloudflare-origin-ca.pem /usr/local/share/ca-certificates/cloudflare-origin-ca.crt
      - update-ca-certificates
      - wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
      - chmod +x /usr/local/bin/mc
      - /home/${var.user_name}/setup-backup-timer.sh ${var.user_name}
      - sleep 30
      - /home/${var.user_name}/restore-backup.sh
      - cd /home/${var.user_name} && docker-compose restart
%{ endif }
  EOF

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
}

# Attach firewall to server
resource "hcloud_firewall_attachment" "web_firewall_attachment" {
  firewall_id = hcloud_firewall.web_firewall.id
  server_ids  = [hcloud_server.node1.id]
}

# Outputs
output "server_ip" {
  description = "Public IP address of the server"
  value       = hcloud_server.node1.ipv4_address
}

output "server_name" {
  description = "Name of the created server"
  value       = hcloud_server.node1.name
}

output "ssh_command" {
  description = "Command to SSH into the server"
  value       = "ssh ${var.user_name}@${hcloud_server.node1.ipv4_address}"
}
