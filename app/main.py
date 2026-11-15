import os
from pathlib import Path
from .telemetry import setup_telemetry
# Deve rodar ANTES de criar o FastAPI para a instrumentação automática funcionar.
TELEMETRIA_ATIVA = setup_telemetry()
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from .databricks_data import configured, snapshot, live_data
from pydantic import BaseModel, Field
import httpx
from .knowledge import search, SOURCES, CHUNKS
from .service import answer
from .weather import forecast

app=FastAPI(title='Belka AI — Protótipo acadêmico',version='0.1.0',description='Assistente de orientação; não emite alertas oficiais.')
STATIC=Path(__file__).parent/'static'

class Ask(BaseModel):
    pergunta:str=Field(min_length=3,max_length=500)
    configuracao:str=Field(default='agent',pattern='^(baseline|rag|rag_lora|agent|agent_lora)$')
    demo:bool=False
    limiar:float=Field(default=0.20,ge=0,le=10)

@app.get('/')
def homepage():return FileResponse(STATIC/'index.html')

@app.get('/monitoramento')
def monitoring_page():return FileResponse(STATIC/'monitoramento.html')

@app.get('/assistente')
def assistant_page():return FileResponse(STATIC/'assistente.html')

@app.get('/api/monitoramento/dados')
def monitoring_data():
    if not configured():
        return JSONResponse(snapshot(), headers={'Cache-Control': 'no-store'})
    try:
        return JSONResponse(live_data(), headers={'Cache-Control': 'no-store'})
    except Exception as exc:
        # Erro explícito: nunca mostrar snapshot fingindo que a consulta foi atualizada.
        raise HTTPException(status_code=503, detail='Não foi possível consultar o Databricks. Verifique credenciais, SQL Warehouse e tabelas Ouro.') from exc

@app.get('/health')
def health(): return {'status':'ok','versao':'0.1.0','llm':'Ollama local (configurável)','modo_demo_disponivel':True,'telemetria':TELEMETRIA_ATIVA}

@app.get('/api/fontes')
def fontes():return {'fontes':list(SOURCES.values()),'quantidade_trechos':len(CHUNKS)}

@app.get('/api/busca')
def busca(pergunta:str,limiar:float=0.20):return {'resultados':search(pergunta,threshold=limiar)}

@app.post('/api/perguntar')
async def perguntar(req:Ask):
    try: return await answer(req.pergunta,req.configuracao,req.demo,req.limiar)
    except httpx.HTTPError as e: raise HTTPException(503,detail='LLM local indisponível. Inicie Ollama e baixe o modelo, ou escolha modo demo.') from e
    except ImportError as e: raise HTTPException(503,detail='Modo LoRA indisponível neste ambiente (requer torch/transformers/peft). Use rag ou agent.') from e

@app.get('/api/clima')
async def clima(latitude:float=-23.55,longitude:float=-46.63):
    # Minimização (LGPD): ~1 km de precisão basta para a previsão; não processar a posição exata.
    latitude,longitude=round(latitude,2),round(longitude,2)
    try:return await forecast(latitude,longitude)
    except ValueError as e:raise HTTPException(422,detail=str(e)) from e
    except (httpx.HTTPError,KeyError,TypeError) as e:raise HTTPException(503,detail='Previsão meteorológica indisponível no momento; não exibir valores antigos como atuais.') from e
