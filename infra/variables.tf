variable "resource_group_name" {
  description = "Resource group da aplicação (criado pelo bootstrap; o deploy só tem permissão nele)."
  type        = string
  default     = "rg-belka"
}

variable "prefix" {
  description = "Prefixo dos nomes dos recursos."
  type        = string
  default     = "belka"
}

variable "api_image" {
  description = "Imagem da API, ex.: ghcr.io/usuario/belka-api:<sha>."
  type        = string
}

variable "ollama_image" {
  description = "Imagem do Ollama com o modelo embutido, ex.: ghcr.io/usuario/belka-ollama:<hash>."
  type        = string
}

variable "alert_email" {
  description = "E-mail que recebe os alertas."
  type        = string
  sensitive   = true
}

variable "api_min_replicas" {
  description = "Réplicas mínimas da API (1 = sem partida a frio para o avaliador)."
  type        = number
  default     = 1
}

variable "ollama_min_replicas" {
  description = "Réplicas mínimas do LLM. 0 = escala a zero (barato); use 1 durante a avaliação."
  type        = number
  default     = 0
}

variable "databricks_server_hostname" {
  description = "Opcional: hostname do SQL Warehouse (camada Ouro)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "databricks_http_path" {
  description = "Opcional: HTTP path do SQL Warehouse."
  type        = string
  default     = ""
  sensitive   = true
}

variable "databricks_token" {
  description = "Opcional: token de acesso ao Databricks (vem do GitHub Secrets)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  type = map(string)
  default = {
    projeto    = "belka-citizentech"
    disciplina = "secure-devops-cloud"
    gerenciado = "terraform"
  }
}
