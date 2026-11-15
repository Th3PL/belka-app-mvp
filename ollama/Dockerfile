# Imagem do LLM local (Ollama) com o modelo já embutido + proxy de autenticação (Caddy).
#
# Por que o proxy: a assinatura Azure for Students só cria ambientes Container Apps "Express",
# que não têm descoberta de serviços internos — apps se comunicam pela URL pública.
# O Ollama não tem autenticação, então ele escuta só em 127.0.0.1 e o Caddy (porta 8080)
# exige "Authorization: Bearer <OLLAMA_API_KEY>"; qualquer outra chamada recebe 401.
#
# Atualize as versões em https://hub.docker.com/r/ollama/ollama/tags e https://hub.docker.com/_/caddy
ARG OLLAMA_VERSION=0.6.8
ARG CADDY_VERSION=2.8.4

FROM caddy:${CADDY_VERSION}-alpine AS caddy

FROM ollama/ollama:${OLLAMA_VERSION}

ARG MODEL=qwen2.5:1.5b
ENV OLLAMA_MODELS=/models \
    OLLAMA_KEEP_ALIVE=30m \
    XDG_CONFIG_HOME=/tmp \
    XDG_DATA_HOME=/tmp

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0755 start.sh /usr/local/bin/start.sh

RUN set -e; \
    mkdir -p /models; \
    (OLLAMA_HOST=127.0.0.1:11434 ollama serve >/tmp/ollama-build.log 2>&1 &); \
    i=0; until OLLAMA_HOST=127.0.0.1:11434 ollama list >/dev/null 2>&1; do i=$((i+1)); if [ "$i" -gt 60 ]; then cat /tmp/ollama-build.log; exit 1; fi; sleep 1; done; \
    OLLAMA_HOST=127.0.0.1:11434 ollama pull "${MODEL}"; \
    useradd --system --uid 10001 --create-home ollama; \
    chown -R 10001:10001 /models; \
    rm -f /tmp/ollama-build.log

# Processo sem root (o Ollama grava a chave de identidade em ~/.ollama).
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD ["sh", "-c", "OLLAMA_HOST=127.0.0.1:11434 ollama list >/dev/null"]
ENTRYPOINT ["/usr/local/bin/start.sh"]
