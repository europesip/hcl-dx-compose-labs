"""Lab 3B · MCP Server propio de EUROPESIP para HCL DX IQ.

Un MCP Server es un servicio que publica "herramientas" (funciones con nombre, descripción y
parámetros) que el LLM puede decidir llamar. Este expone dos, por HTTP "streamable" en /mcp
(el mismo transporte que el MCP Server de HCL):
  - consultar_faq_europesip(tema): base de conocimiento de EUROPESIP (p. ej. horario de soporte),
    información que el modelo no puede saber por sí mismo.
  - eco_europesip(texto): diagnóstico.

Registra en el log cada petición: método, ruta y NOMBRES de cabeceras y cookies (nunca sus
valores), para ver qué le envía el IQ Integrator. SDK oficial de MCP para Python (FastMCP).
"""
import logging, os
import uvicorn
from starlette.requests import Request
from starlette.responses import PlainTextResponse
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("europesip-mcp")

FAQ = {
    "soporte": "El soporte de EUROPESIP para HCL DX atiende de lunes a viernes de 9:00 a 18:00 (hora de Madrid) en soporte@europesip.com.",
    "laboratorio": "El laboratorio del webinar de EUROPESIP es un clúster k3s con HCL DX Compose CF238, IQ 1.0.2 y LiteLLM.",
    "iq": "En EUROPESIP, IQ usa LiteLLM con Claude a través de OpenRouter. LiteLLM no lo proporciona HCL: lo instalamos nosotros.",
}

mcp = FastMCP(
    "europesip-kb",
    host="0.0.0.0",
    port=int(os.getenv("PORT", "3000")),
    stateless_http=True,       # como el MCP de HCL: sin sesiones, GET /mcp -> 405
    json_response=True,
    # Laboratorio: sin validación de la cabecera Host (el Integrator llama por el nombre del Service)
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)

@mcp.tool()
def consultar_faq_europesip(tema: str) -> str:
    """Consulta la base de conocimiento interna de EUROPESIP (empresa partner de HCL).
    Úsala cuando el usuario pregunte por el soporte de EUROPESIP, su laboratorio o cómo
    tiene configurado IQ. Temas disponibles: soporte, laboratorio, iq."""
    log.info("TOOL consultar_faq_europesip tema=%r", tema)
    t = tema.strip().lower()
    for clave, texto in FAQ.items():
        if clave in t:
            return texto
    return "No hay información sobre ese tema. Temas disponibles: " + ", ".join(FAQ)

@mcp.tool()
def eco_europesip(texto: str) -> str:
    """Herramienta de diagnóstico: devuelve el texto recibido con un prefijo.
    Úsala solo si el usuario pide expresamente probar el eco de EUROPESIP."""
    log.info("TOOL eco_europesip")
    return f"[europesip-mcp] {texto}"

@mcp.custom_route("/probe/ready", methods=["GET"])
async def probe_ready(request: Request) -> PlainTextResponse:
    """El IQ Integrator llama a /probe/ready antes de pedir las herramientas (como al MCP de HCL)."""
    return PlainTextResponse("OK")

app = mcp.streamable_http_app()

class LogRequests:
    """Middleware ASGI: registra método, ruta y nombres de cabeceras/cookies (sin valores)."""
    def __init__(self, inner):
        self.inner = inner
    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            hdrs = {k.decode().lower(): v.decode(errors="replace") for k, v in scope["headers"]}
            cookies = sorted(c.split("=", 1)[0].strip() for c in hdrs.get("cookie", "").split(";") if "=" in c)
            log.info("REQ %s %s headers=%s cookies=%s", scope["method"], scope["path"],
                     sorted(h for h in hdrs if h != "cookie"), cookies or "-")
        await self.inner(scope, receive, send)

if __name__ == "__main__":
    uvicorn.run(LogRequests(app), host="0.0.0.0", port=int(os.getenv("PORT", "3000")), log_level="warning")
