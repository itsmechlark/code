variable "location" {
  type        = string
  default     = "southeastasia"
  description = "The Azure location where all resources should be created"
}

variable "name" {
  type        = string
  default     = "code"
  description = "Virtual machine name"
}

variable "username" {
  type        = string
  default     = "code"
  description = "VM Username"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH Public Key."
}

variable "dns_servers" {
  type        = list(string)
  default     = ["1.1.1.2", "1.0.0.2"]
  description = "DNS Servers"
}

variable "cloudflare_zone_id" {
  type = string
}

variable "argo_tunnel_id" {
  type = string
}

variable "argo_tunnel_name" {
  type = string
}

variable "argo_tunnel_secret" {
  type = string
}

variable "argo_tunnel_tag" {
  type = string
}

variable "whitelisted_ips" {
  type = list(string)
  default     = []
}