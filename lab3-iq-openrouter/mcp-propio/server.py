"""Lab 3B · MCP Server propio de EUROPESIP para HCL DX IQ.

Un MCP Server es un servicio que publica "herramientas" (funciones con nombre, descripción y
parámetros) que el LLM puede decidir llamar. Este expone cuatro, por HTTP "streamable" en /mcp
(el mismo transporte que el MCP Server de HCL):
  - consultar_servicios_europesip(): quién es EUROPESIP y qué servicios ofrece.
  - consultar_faq_europesip(tema): soporte, IA, soberanía digital, laboratorios, contacto...
    Información que el modelo no puede saber por sí mismo.
  - figma_web_to_dx(origen) -> se muestra como "figma&web-to-dx": presenta la herramienta de
    EUROPESIP que genera componentes WCM / Blueprint a partir de Figma, pantallazos o URLs.
  - eco_europesip(texto): diagnóstico.

Los nombres técnicos solo usan [a-zA-Z0-9_-] (lo exige IQ/Claude); el nombre visible va en "title".
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

WEB = "https://www.europesip.com"
REPO_LABS = "https://github.com/europesip/hcl-dx-compose-labs"

SERVICIOS = (
    "EUROPESIP es una empresa especializada en productos de HCL e IBM, con amplia experiencia en "
    "portales (HCL Digital Experience) y en HCL Domino. Tiene además fuertes conocimientos en "
    "inteligencia artificial: ha desarrollado herramientas que facilitan el uso de la IA y aceleran "
    "el desarrollo, como su herramienta figma&web-to-dx, que se integra con HCL DX IQ para generar "
    "componentes Blueprint a partir de diseños de Figma, pantallazos o URLs de sitios web. "
    "EUROPESIP pone un fuerte énfasis en la soberanía digital. "
    f"Más información en {WEB}."
)

FAQ = {
    "soporte": "El soporte de EUROPESIP para HCL DX atiende de lunes a viernes de 9:00 a 18:00 (hora de Madrid) en soporte@europesip.com.",
    "servicios": SERVICIOS,
    "ia": ("EUROPESIP tiene fuertes conocimientos en inteligencia artificial y ha desarrollado herramientas "
           "que facilitan el uso de la IA y aceleran el desarrollo; por ejemplo, figma&web-to-dx, integrada "
           f"con HCL DX IQ para crear componentes Blueprint desde Figma, pantallazos o URLs. Más información en {WEB}."),
    "soberania": ("EUROPESIP hace un fuerte hincapié en la soberanía digital: que las organizaciones mantengan el "
                  "control de sus datos, sus plataformas y sus decisiones tecnológicas. "
                  f"Más información en {WEB}."),
    "laboratorios": ("Los laboratorios de EUROPESIP para instalar HCL DX Compose CF238 desde cero en Kubernetes "
                     "(DX base, LDAP, PostgreSQL, IQ con OpenRouter, MCP propio y búsqueda con OpenSearch) están "
                     f"publicados en {REPO_LABS}. Cada laboratorio tiene su guía y scripts listos para ejecutar."),
    "contacto": f"Para más información sobre EUROPESIP y sus servicios: {WEB}. Soporte: soporte@europesip.com.",
    "iq": "En EUROPESIP, IQ usa LiteLLM con Claude a través de OpenRouter. LiteLLM no lo proporciona HCL: lo instalamos nosotros.",
}
# Se añade a cada respuesta: el modelo tiende a completar con datos que no le hemos dado
# ("partner oficial", servicios inventados...). Le pedimos que se ciña a lo que devuelve la herramienta.
CINE = ("\n\n[Instrucción para el asistente: responde usando solo esta información de EUROPESIP; "
        "no añadas servicios, certificaciones ni datos que no aparezcan aquí. Para cualquier otro "
        f"detalle, remite a {WEB}.]")

# Palabras con las que el modelo puede pedir cada tema. El ORDEN importa: los temas más
# específicos primero ("soberanía" contiene "ia"; "laboratorios de HCL" contiene "hcl").
ALIAS = {
    "soberania": ["soberan", "sovereign"],
    "laboratorios": ["laborator", "lab", "compose", "instalac", "repo", "github", "webinar"],
    "soporte": ["soporte", "horario", "support"],
    "iq": ["litellm", "openrouter"],
    "ia": ["inteligencia", "artificial", "herramienta"],
    "contacto": ["contact", "pagina", "página", "web"],
    "servicios": ["servicio", "empresa", "quien", "quién", "europesip", "portal", "domino", "hcl", "ibm"],
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
def consultar_servicios_europesip() -> str:
    """Describe a EUROPESIP y los servicios que ofrece (empresa especializada en productos de HCL
    e IBM: portales HCL DX, HCL Domino, inteligencia artificial, soberanía digital). Úsala cuando el
    usuario pregunte quién es EUROPESIP, a qué se dedica o qué servicios ofrece."""
    log.info("TOOL consultar_servicios_europesip")
    return SERVICIOS + CINE

@mcp.tool()
def consultar_faq_europesip(tema: str) -> str:
    """Consulta la base de conocimiento de EUROPESIP. Úsala cuando el usuario pregunte por el
    soporte de EUROPESIP (horario), su experiencia en IA, la soberanía digital, sus laboratorios
    de instalación de HCL DX Compose, su web o cómo contactar. Temas: soporte, servicios, ia,
    soberania, laboratorios, contacto, iq."""
    log.info("TOOL consultar_faq_europesip tema=%r", tema)
    t = tema.strip().lower()
    if t in FAQ:                                   # el tema exacto
        return FAQ[t] + CINE
    for clave, palabras in ALIAS.items():          # si no, por palabras clave
        if any(p in t for p in palabras):
            return FAQ[clave] + CINE
    return "No hay información sobre ese tema. Temas disponibles: " + ", ".join(FAQ)

@mcp.tool(name="figma_web_to_dx", title="figma&web-to-dx")
def figma_web_to_dx(origen: str = "") -> str:
    """figma&web-to-dx: diseña páginas web o componentes de WCM / Blueprint de HCL DX a partir de un
    diseño de Figma, un pantallazo o la URL de un sitio externo. Úsala cuando el usuario quiera
    crear un componente, una plantilla o una página de DX desde un diseño, una imagen o una web.
    Parámetro origen: la URL de Figma, del pantallazo o del sitio (opcional)."""
    log.info("TOOL figma_web_to_dx origen=%r", origen[:200])
    return ("EUROPESIP tiene una herramienta MCP, figma&web-to-dx, que se integra con HCL DX IQ para "
            "facilitar y acelerar el desarrollo de componentes Blueprint a partir de simples URLs de "
            "Figma, pantallazos de webs o URLs de sitios. Para más información, contacta con EUROPESIP: "
            f"{WEB}." + CINE)

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
