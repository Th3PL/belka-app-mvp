# Belka App — MVP mobile-first

Aplicação web responsiva integrada, a partir dos repositórios acadêmicos Big Data e Gen AI. Sem PWA e sem necessidade de app nativo.

## Ficha Técnica do MVP

| Campo | Conteúdo |
|---|---|
| Nome do produto | Belka |
| Cidadão e território | _preencher: ex. moradores de áreas de risco de alagamento em São Paulo_ |
| Problema, em uma frase | _preencher_ |
| Proposta de valor | _preencher_ |
| Arquitetura: componentes | API FastAPI + LLM local (Ollama qwen2.5:1.5b) + RAG + camada Ouro Databricks, em Azure Container Apps — ver [docs/ENTREGA-CLOUD.md](docs/ENTREGA-CLOUD.md) |
| Fontes de dados | Open-Meteo (previsão), base de conhecimento `base/` (Defesa Civil etc.), camada Ouro do Databricks |
| Modelos de IA utilizados | Qwen2.5-1.5B-Instruct (Ollama) + adaptador LoRA próprio (`outputs/belka-lora`) |
| URL do MVP | _preencher após o deploy: https://belka-api.xxxx.brazilsouth.azurecontainerapps.io_ |
| Repositório | _preencher: https://github.com/USUARIO/belka-app-mvp_ |
| Indicadores de impacto | _preencher_ |
| ODS conectados | _preencher: ex. ODS 11, ODS 13_ |

**Integrantes:** _Nome 1 (RM), Nome 2 (RM), ..._

## Telas
- `/` — início
- `/monitoramento` — dashboard original de Big Data, alimentado diretamente pela camada Ouro do Databricks se configurado; caso contrário usa snapshot histórico (`/api/monitoramento/dados`). Não é um sistema de alertas em tempo real.
- `/assistente` — interface original de Gen AI, com agente, RAG, LoRA e previsão Open-Meteo.

## Executar com Docker (recomendado)

Pré-requisito: Docker Desktop.

```bash
docker compose up --build
```

Abra http://localhost:8000. O primeiro build baixa o modelo `qwen2.5:1.5b` (~1 GB) para dentro da imagem do Ollama. O LLM não é exposto fora da rede do compose.

Variáveis opcionais (Databricks) vão em um arquivo `.env` baseado em `.env.example` — o `.env` é ignorado pelo git.

## Executar sem Docker (Git Bash no Windows)
```bash
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements.txt
ollama pull qwen2.5:1.5b
uvicorn app.main:app --reload --host 0.0.0.0
```

O Ollama deve estar em execução para respostas reais nos modos `agent`, `rag` e `baseline`. O modo demonstração da tela é extrativo e não usa IA. Para usar `rag_lora` ou `agent_lora`, instale também `pip install -r requirements-lora.txt` (o modelo-base `Qwen/Qwen2.5-1.5B-Instruct` é baixado no primeiro uso). Os modos LoRA **não** estão disponíveis na imagem de produção (torch é pesado demais para o container); a API responde 503 com mensagem clara.

## Deploy na Azure (produção)

Infraestrutura 100% em código (Terraform em [`infra/`](infra/)) e deploy automático pelo GitHub Actions ([`.github/workflows/devsecops.yml`](.github/workflows/devsecops.yml)).

```
push -> Gitleaks + Semgrep -> build -> Trivy (imagem e config) -> push GHCR -> terraform apply -> teste de fumaça
```

### 1. Bootstrap (uma vez)
Requer Azure CLI logado (`az login`) com uma assinatura (ex.: Azure for Students).
```bash
GITHUB_REPO="USUARIO/belka-app-mvp" bash infra/bootstrap.sh
```
Cria o resource group, o Storage Account do state remoto e a identidade OIDC do GitHub Actions, e imprime os valores a cadastrar.

### 2. GitHub
- **Settings > Secrets and variables > Actions > Secrets:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ALERT_EMAIL` e, opcionalmente, `DATABRICKS_SERVER_HOSTNAME`, `DATABRICKS_HTTP_PATH`, `DATABRICKS_TOKEN`.
- **Variables:** `AZURE_RESOURCE_GROUP`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT` e, opcionalmente, `OLLAMA_MIN_REPLICAS` (`1` deixa o LLM sempre quente durante a avaliação).
- **Settings > Environments:** criar `production`.

### 3. Primeiro deploy
1. `git push` na `main`. O job de build publica as imagens no GHCR.
2. Na primeira vez, em **GitHub > Packages**, torne públicos os pacotes `belka-api` e `belka-ollama` (o Container Apps baixa imagens públicas sem credencial) e reexecute o workflow.
3. A URL pública aparece no resumo da execução (`terraform output api_url`).

### Destruir tudo após a avaliação
```bash
cd infra
terraform init -backend-config="resource_group_name=rg-belka-tfstate" -backend-config="storage_account_name=<SEU_SA>"
terraform destroy -var api_image=x -var ollama_image=x -var alert_email=x
```

## Conexão opcional com Databricks

A fonte é o mesmo modelo estrela criado no notebook `ouro_belka`:
`workspace.belka.ouro_fato_risco_hora`, `ouro_dim_municipio`, `ouro_dim_tempo`, `ouro_dim_nivel_risco`.

1. Confirme que as quatro tabelas estão populadas e que há um SQL Warehouse disponível com permissão SELECT.
2. Em **SQL Warehouses > seu warehouse > Connection details**, copie **Server hostname** e **HTTP path**. Gere um token pessoal de acesso.
3. Localmente, coloque os valores no `.env` (não versionado) ou exporte no terminal:

```bash
pip install -r requirements-databricks.txt
export DATABRICKS_SERVER_HOSTNAME='<seu-workspace>.cloud.databricks.com'
export DATABRICKS_HTTP_PATH='/sql/1.0/warehouses/<id-do-warehouse>'
export DATABRICKS_TOKEN='<seu-token>'
uvicorn app.main:app --reload --host 0.0.0.0
```

Em produção os três valores ficam em **GitHub Secrets** e chegam ao container como *secrets* do Azure Container Apps. Nunca publique o token no GitHub, no HTML, em screenshots ou em arquivos versionados — o Gitleaks barra o pipeline se isso acontecer. Se a consulta falhar, a API devolve 503 em vez de trocar silenciosamente para o snapshot. Sem as três variáveis, a aplicação usa o JSON histórico.

## Segurança e LGPD (resumo)
- Containers sem root; LLM sem acesso pela internet; nenhuma VM nem porta de administração (SSH/RDP) existe.
- Segredos só em GitHub Secrets / secrets do Container Apps; login do pipeline na Azure via OIDC (sem senha).
- Coordenadas arredondadas (~1 km); query string removida da telemetria; texto das perguntas não é registrado; IP mascarado no Application Insights.
- Detalhes: [docs/ENTREGA-CLOUD.md](docs/ENTREGA-CLOUD.md).

## Limites
- Sem credenciais, o dashboard contém exportação estática; com credenciais, consulta a camada Ouro no momento da requisição.
- O LLM roda em CPU no Container Apps: respostas levam de 10 a 30 s, e a primeira após inatividade pode levar ~1–2 min (escala a zero). O modo demo não depende do LLM.
- Indicadores de risco são experimentais e não são alertas oficiais da Defesa Civil.
