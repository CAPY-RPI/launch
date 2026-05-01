variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "domain_name" {
  description = "The base domain name (e.g., example.com)"
  type        = string
}

variable "tunnel_name" {
  description = "The name of the Cloudflare Tunnel"
  type        = string
  default     = "homelab-tunnel"
}
