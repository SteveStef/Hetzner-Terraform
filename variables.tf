# Variables
variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "ssh_key_path" {
  description = "Path to SSH public key"
  type        = string
}

variable "my_ip" {
  description = "Your IP address for SSH access"
  type        = string
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx11"
}

variable "server_location" {
  description = "Hetzner server location"
  type        = string
  default     = "ash"
}

variable "github_repo" {
  description = "GitHub repository URL"
  type        = string
}

variable "app_name" {
  description = "Name of the app when cloned"
  type        = string
}

# =============================

variable "image_type" {
  description = "Name of the server"
  type        = string
  default     = "ubuntu-22.04"
}

variable "server_name" {
  description = "Name of the server"
  type        = string
  default     = "my-server"
}

variable "ssh_key_name" {
  description = "Name of the SSH key"
  type        = string
  default     = "deployer-ssh-key"
}

variable "firewall_name" {
  description = "Name of the firewall"
  type        = string
  default     = "web-firewall"
}

variable "user_name" {
  description = "Username to create on the server"
  type        = string
  default     = "ubuntu"
}

variable "backup_enabled" {
  description = "Whether backup system is enabled"
  type        = bool
  default     = false
}
