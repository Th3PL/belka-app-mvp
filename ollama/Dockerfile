# Imagem do LLM local (Ollama) com o modelo já embutido.
# Embutir o modelo evita baixar ~1 GB a cada partida a frio no Azure Container Apps.
# Atualize OLLAMA_VERSION para a versão estável mais recente em https://hub.docker.com/r/ollama/ollama/tags
ARG OLLAMA_VERSION=0.6.8
FROM ollama/ollama:${OLLAMA_VERSION}

ARG MODEL=qwen2.5:1.5b
ENV OLLAMA_MODELS=/models \
    OLLAMA_HOST=0.0.0.0:11434 \
    OLLAMA_KEEP_ALIVE=30m

RUN set -e; \
    mkdir -p /models; \
    (ollama serve >/tmp/ollama-build.log 2>&1 &); \
    i=0; until ollama list >/dev/null 2>&1; do i=$((i+1)); if [ "$i" -gt 60 ]; then cat /tmp/ollama-build.log; exit 1; fi; sleep 1; done; \
    ollama pull "${MODEL}"; \
    useradd --system --uid 10001 --create-home ollama; \
    chown -R 10001:10001 /models; \
    rm -f /tmp/ollama-build.log

# Processo sem root (o Ollama grava a chave de identidade em ~/.ollama).
USER 10001
EXPOSE 11434
# ENTRYPOINT ["/bin/ollama"] e CMD ["serve"] herdados da imagem oficial.
