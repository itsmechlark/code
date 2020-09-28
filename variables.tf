variable "location" {
  type        = string
  default     = "southeastasia"
  description = "The Azure location where all resources should be created"
}

variable "name" {
  type        = string
  default     = "coder"
  description = "Virtual machine name"
}

variable "username" {
  type        = string
  default     = "coder"
  description = "VM Username"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH Public Key (base64)"
}