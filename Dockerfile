# syntax=docker/dockerfile:1
# Imagem da API Belka (FastAPI). Multi-stage: compiladores e cache do pip
# ficam no estágio de build; a imagem final leva só o venv e o código.

FROM python:3.12-slim AS build
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
WORKDIR /build
COPY requirements.txt requirements-databricks.txt ./
RUN pip install -r requirements-databricks.txt

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH=/opt/venv/bin:$PATH
# Aplica correções de segurança do SO publicadas após a imagem base (Trivy barra HIGH/CRITICAL)
# e cria usuário de sistema sem shell de login e sem home: o processo nunca roda como root.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin belka
WORKDIR /srv
COPY --from=build /opt/venv /opt/venv
# Código pertence ao root e é somente leitura para o usuário da aplicação.
COPY app/ ./app/
COPY base/ ./base/
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)"]
# --no-access-log: o log de acesso do uvicorn gravaria a query string
# (latitude/longitude do cidadão). A telemetria de requisições vai pelo App Insights, sem query.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log", "--proxy-headers"]
