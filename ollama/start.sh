#!/bin/sh
# Sobe o Ollama apenas em loopback e o proxy Caddy (porta 8080) que exige o token.
set -eu

# Sem token forte o proxy aceitaria "Bearer " vazio: recusa subir.
OLLAMA_API_KEY="${OLLAMA_API_KEY:-}"
if [ "${#OLLAMA_API_KEY}" -lt 32 ]; then
  echo "OLLAMA_API_KEY ausente ou com menos de 32 caracteres; abortando." >&2
  exit 1
fi

OLLAMA_HOST=127.0.0.1:11434 /bin/ollama serve &
exec /usr/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
