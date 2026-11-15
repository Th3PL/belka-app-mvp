data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

locals {
  location = data.azurerm_resource_group.main.location

  # Apenas o "liga/desliga" deixa de ser sensível; os valores continuam protegidos.
  use_databricks = nonsensitive(var.databricks_token != "" && var.databricks_http_path != "" && var.databricks_server_hostname != "")

  databricks_values = {
    "databricks-hostname"  = var.databricks_server_hostname
    "databricks-http-path" = var.databricks_http_path
    "databricks-token"     = var.databricks_token
  }

  # nome da variável de ambiente => nome do secret no Container App
  databricks_env = local.use_databricks ? {
    DATABRICKS_SERVER_HOSTNAME = "databricks-hostname"
    DATABRICKS_HTTP_PATH       = "databricks-http-path"
    DATABRICKS_TOKEN           = "databricks-token"
  } : {}
}

# ---------- Observabilidade ----------
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.prefix}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1 # teto de custo
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.prefix}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  retention_in_days   = 30
  # IP do cliente é mascarado (0.0.0.0) — padrão mantido de propósito (LGPD).
  ip_masking_enabled = true
  tags               = var.tags
}

# ---------- Ambiente de containers (sem VM, sem SSH, sem porta admin) ----------
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.prefix}"
  location                   = local.location
  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = var.tags
}

# LLM: ingress SOMENTE interno — inacessível pela internet.
resource "azurerm_container_app" "ollama" {
  name                         = "${var.prefix}-ollama"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = var.tags

  template {
    min_replicas = var.ollama_min_replicas
    max_replicas = 1

    container {
      name   = "ollama"
      image  = var.ollama_image
      cpu    = 2
      memory = "4Gi"
    }
  }

  ingress {
    external_enabled = false
    target_port      = 11434
    transport        = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# API pública: única porta exposta é HTTPS 443 gerenciado pela Azure.
resource "azurerm_container_app" "api" {
  name                         = "${var.prefix}-api"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"
  tags                         = var.tags

  secret {
    name  = "appinsights-connection-string"
    value = azurerm_application_insights.main.connection_string
  }

  dynamic "secret" {
    for_each = toset(values(local.databricks_env))
    content {
      name  = secret.key
      value = local.databricks_values[secret.key]
    }
  }

  template {
    min_replicas = var.api_min_replicas
    max_replicas = 3

    container {
      name   = "api"
      image  = var.api_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "OLLAMA_URL"
        # FQDN do ingress INTERNO (só resolve/aceita dentro do ambiente), com TLS gerenciado.
        # http:// recebe 301 para HTTPS e ambientes "express" não permitem allowInsecure.
        value = "https://${azurerm_container_app.ollama.ingress[0].fqdn}"
      }
      env {
        name  = "OLLAMA_MODEL"
        value = "qwen2.5:1.5b"
      }
      env {
        name  = "OTEL_SERVICE_NAME"
        value = "belka-api"
      }
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }

      dynamic "env" {
        for_each = local.databricks_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }
      readiness_probe {
        transport = "HTTP"
        port      = 8000
        path      = "/health"
      }
    }
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false # HTTP é redirecionado para HTTPS
    target_port                = 8000
    transport                  = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
