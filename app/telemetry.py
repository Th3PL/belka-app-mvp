"""Observabilidade com Azure Application Insights (OpenTelemetry).

Ativa somente quando APPLICATIONINSIGHTS_CONNECTION_STRING existe (produção).
Localmente nada é enviado.

LGPD: a query string (ex.: latitude/longitude em /api/clima e nas chamadas ao
Open-Meteo) é removida de toda URL antes de a telemetria sair do container.
O texto das perguntas nunca é registrado (vai no corpo do POST, que não é coletado).
"""
import os
from urllib.parse import urlsplit, urlunsplit

from opentelemetry.sdk.trace import SpanProcessor

_URL_KEYS = ("http.url", "url.full", "http.target")
_DROP_KEYS = ("url.query",)


def _sem_query(value):
    if not isinstance(value, str) or "?" not in value:
        return value
    parts = urlsplit(value)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


class RemoverQueryString(SpanProcessor):
    """Limpa as URLs no início do span (no fim os atributos já são imutáveis).

    As instrumentações HTTP (ASGI/FastAPI, requests, urllib) gravam a URL nos
    atributos passados ao criar o span, então eles já existem em on_start.
    """

    def on_start(self, span, parent_context=None):
        attrs = span.attributes or {}
        for key in _URL_KEYS:
            if key in attrs:
                span.set_attribute(key, _sem_query(attrs[key]))
        for key in _DROP_KEYS:
            if key in attrs:
                span.set_attribute(key, "")


def setup_telemetry() -> bool:
    connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if not connection_string:
        return False

    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor(
        connection_string=connection_string,
        span_processors=[RemoverQueryString()],
    )
    return True
