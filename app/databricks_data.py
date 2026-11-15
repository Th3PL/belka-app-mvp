"""Leitura somente das tabelas Ouro do projeto Belka (Databricks SQL)."""
import json
import os
from datetime import datetime
from decimal import Decimal
from pathlib import Path

STATIC_SNAPSHOT = Path(__file__).parent / 'static' / 'belka_mvp.json'


def configured():
    return all(os.getenv(k) for k in ('DATABRICKS_SERVER_HOSTNAME', 'DATABRICKS_HTTP_PATH', 'DATABRICKS_TOKEN'))


def snapshot():
    data = json.loads(STATIC_SNAPSHOT.read_text(encoding='utf-8'))
    data['origem_dados'] = 'snapshot_historico'
    return data


def live_data():
    # Import opcional: a aplicação funciona sem o connector quando não configurado.
    from databricks import sql

    with sql.connect(
        server_hostname=os.environ['DATABRICKS_SERVER_HOSTNAME'].replace('https://', '').strip('/'),
        http_path=os.environ['DATABRICKS_HTTP_PATH'],
        access_token=os.environ['DATABRICKS_TOKEN'],
    ) as conn:
        def rows(statement):
            with conn.cursor() as cur:
                cur.execute(statement)
                cols = [c[0] for c in cur.description]
                return [dict(zip(cols, r)) for r in cur.fetchall()]

        municipalities = rows('SELECT municipio_id, municipio_nome, uf, populacao, ano_populacao, latitude, longitude, contexto_territorio FROM workspace.belka.ouro_dim_municipio ORDER BY municipio_nome')
        levels = rows('SELECT * FROM workspace.belka.ouro_dim_nivel_risco ORDER BY nivel_id')
        hours = rows('''
            SELECT f.municipio_id, m.municipio_nome, f.data_hora,
                   t.data, t.hora, t.periodo_dia,
                   f.nivel_id, n.nivel_nome, f.risco_principal, f.motivo,
                   f.temperatura_c, f.precipitacao_mm, f.chuva_24h_mm,
                   f.chuva_72h_mm, f.umidade_pct, f.rajada_kmh
            FROM workspace.belka.ouro_fato_risco_hora f
            JOIN workspace.belka.ouro_dim_municipio m ON f.municipio_id = m.municipio_id
            JOIN workspace.belka.ouro_dim_tempo t ON f.tempo_id = t.tempo_id
            JOIN workspace.belka.ouro_dim_nivel_risco n ON f.nivel_id = n.nivel_id
            ORDER BY f.data_hora, f.municipio_id
        ''')

    # A dimensão LGPD é simulada e não precisa ser consultada: zeramos os contadores
    # para não apresentar valores antigos do snapshot como se fossem atuais.
    for m in municipalities:
        m.update(assinantes=None, assinantes_60_mais=None, recebem_sms=None)
    for h in hours:
        for k in ('data_hora', 'data'):
            if h[k] is not None:
                h[k] = h[k].isoformat(timespec='minutes') if isinstance(h[k], datetime) else str(h[k])
    for collection in (municipalities, levels, hours):
        for row in collection:
            for key, val in row.items():
                if isinstance(val, Decimal):
                    row[key] = float(val)
    if not municipalities or not levels or not hours:
        raise ValueError('Tabelas Ouro sem registros suficientes para o dashboard')
    return {
        'gerado_em': datetime.now().isoformat(timespec='seconds'),
        'origem_dados': 'databricks_ouro',
        'aviso': 'Indicadores experimentais da camada Ouro. Não são alertas oficiais nem necessariamente previsões atuais. Cadastro de assinantes não conectado.',
        'fontes': ['Databricks (camada Ouro)', 'Open-Meteo', 'IBGE'],
        'municipios': municipalities,
        'niveis': levels,
        'horas': hours,
    }
