variable "cluster_name" {
  description = "Nome do cluster k3d"
  type        = string
  default     = "devops-aula"
}

variable "node_count" {
  description = "Quantidade de nós agents"
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1
    error_message = "O cluster precisa ter pelo menos um agent."
  }
}

variable "app_image" {
  description = "Nome da imagem Docker local do Task Manager"
  type        = string
  default     = "task-manager:local"
}

variable "kubeconfig_path" {
  description = "Caminho onde o kubeconfig será salvo"
  type        = string
  default     = "./kubeconfig"
}