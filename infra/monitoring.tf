# ---------- Alerta ----------
resource "azurerm_monitor_action_group" "email" {
  name                = "ag-${var.prefix}-email"
  resource_group_name = data.azurerm_resource_group.main.name
  short_name          = "belkaops"
  tags                = var.tags

  email_receiver {
    name                    = "equipe"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Dispara quando há mais de 3 requisições com falha (5xx) em 5 minutos.
resource "azurerm_monitor_metric_alert" "erros" {
  name                = "alerta-${var.prefix}-erros-5xx"
  resource_group_name = data.azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Belka API: requisições com falha acima do limite (sinal de ouro: erros)."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 3
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}

# Saturação: CPU média da API acima de 80% de 0,5 vCPU (0,4 vCPU = 400.000.000 nanocores).
resource "azurerm_monitor_metric_alert" "saturacao" {
  name                = "alerta-${var.prefix}-cpu"
  resource_group_name = data.azurerm_resource_group.main.name
  scopes              = [azurerm_container_app.api.id]
  description         = "Belka API: CPU alta (sinal de ouro: saturação)."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.App/containerApps"
    metric_name      = "UsageNanoCores"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 400000000
  }

  action {
    action_group_id = azurerm_monitor_action_group.email.id
  }
}

# ---------- Dashboard: 4 sinais de ouro (Workbook do Application Insights) ----------
locals {
  periodo = { durationMs = 86400000 } # últimas 24 h (ajustável na tela)

  workbook = {
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        name = "titulo"
        content = {
          json = "# Belka API — 4 sinais de ouro\nLatência, tráfego, erros e saturação do MVP em produção (Azure Container Apps)."
        }
      },
      {
        type = 3
        name = "latencia"
        content = {
          version       = "KqlItem/1.0"
          title         = "1. Latência (ms) — p50 e p95"
          query         = "requests\n| summarize p50 = percentile(duration, 50), p95 = percentile(duration, 95) by bin(timestamp, 5m)\n| order by timestamp asc"
          size          = 0
          queryType     = 0
          resourceType  = "microsoft.insights/components"
          visualization = "timechart"
          timeContext   = local.periodo
        }
      },
      {
        type = 3
        name = "trafego"
        content = {
          version       = "KqlItem/1.0"
          title         = "2. Tráfego — requisições por rota (5 min)"
          query         = "requests\n| summarize requisicoes = count() by bin(timestamp, 5m), name\n| order by timestamp asc"
          size          = 0
          queryType     = 0
          resourceType  = "microsoft.insights/components"
          visualization = "timechart"
          timeContext   = local.periodo
        }
      },
      {
        type = 3
        name = "erros"
        content = {
          version       = "KqlItem/1.0"
          title         = "3. Erros — falhas e taxa de erro (%)"
          query         = "requests\n| summarize falhas = countif(success == false), taxa_erro_pct = round(100.0 * countif(success == false) / count(), 2) by bin(timestamp, 5m)\n| order by timestamp asc"
          size          = 0
          queryType     = 0
          resourceType  = "microsoft.insights/components"
          visualization = "timechart"
          timeContext   = local.periodo
        }
      },
      {
        type = 10
        name = "saturacao"
        content = {
          version      = "MetricsItem/2.0"
          title        = "4. Saturação — CPU (nanocores) e memória (bytes) da API"
          size         = 0
          chartType    = 2
          resourceType = "microsoft.app/containerapps"
          metricScope  = 0
          resourceIds  = [azurerm_container_app.api.id]
          timeContext  = local.periodo
          metrics = [
            {
              namespace   = "microsoft.app/containerapps"
              metric      = "microsoft.app/containerapps--UsageNanoCores"
              aggregation = 4
            },
            {
              namespace   = "microsoft.app/containerapps"
              metric      = "microsoft.app/containerapps--WorkingSetBytes"
              aggregation = 4
            }
          ]
        }
      }
    ]
    fallbackResourceIds = [azurerm_application_insights.main.id]
  }
}

resource "azurerm_application_insights_workbook" "golden_signals" {
  name                = uuidv5("url", "https://belka/workbook/golden-signals")
  resource_group_name = data.azurerm_resource_group.main.name
  location            = local.location
  display_name        = "Belka - Sinais de Ouro"
  source_id           = lower(azurerm_application_insights.main.id)
  category            = "workbook"
  data_json           = jsonencode(local.workbook)
  tags                = var.tags
}
