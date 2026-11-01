"""Lab 3B · EUROPESIP custom MCP Server for HCL DX IQ.

An MCP Server is a service that publishes "tools" (functions with a name, a description and
parameters) that the LLM can decide to call. This one exposes four, over "streamable" HTTP at /mcp
(the same transport as the HCL MCP Server):
  - europesip_services(): who EUROPESIP is and which services it offers.
  - europesip_faq(topic): support, AI, digital sovereignty, labs, contact...
    Information the model cannot know by itself.
  - figma_web_to_dx(source) -> shown as "figma&web-to-dx": presents the EUROPESIP tool that
    generates WCM / Blueprint components from Figma, screenshots or URLs.
  - europesip_echo(text): diagnostics.

Technical names only use [a-zA-Z0-9_-] (required by IQ/Claude); the display name goes in "title".
The answers are in English; IQ translates them to the user's language when it replies.
Every request is logged: method, path and the NAMES of headers and cookies (never their values),
to see what the IQ Integrator sends. Official MCP SDK for Python (FastMCP).
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
LABS_REPO = "https://github.com/europesip/hcl-dx-compose-labs"

SERVICES = (
    "EUROPESIP is a company specialised in HCL and IBM products, with broad experience in "
    "portals (HCL Digital Experience) and in HCL Domino. It also has strong knowledge of "
    "artificial intelligence: it has developed tools that make AI easier to use and speed up "
    "development, such as its figma&web-to-dx tool, which integrates with HCL DX IQ to generate "
    "Blueprint components from Figma designs, screenshots or website URLs. "
    "EUROPESIP puts a strong emphasis on digital sovereignty. "
    f"More information at {WEB}."
)

FAQ = {
    "support": "EUROPESIP support for HCL DX is available Monday to Friday from 9:00 to 18:00 (Madrid time) at soporte@europesip.com.",
    "services": SERVICES,
    "ai": ("EUROPESIP has strong knowledge of artificial intelligence and has developed tools that make "
           "AI easier to use and speed up development; for example figma&web-to-dx, integrated with "
           f"HCL DX IQ to create Blueprint components from Figma, screenshots or URLs. More information at {WEB}."),
    "sovereignty": ("EUROPESIP puts a strong emphasis on digital sovereignty: organisations keeping control "
                    "of their data, their platforms and their technology decisions. "
                    f"More information at {WEB}."),
    "labs": ("The EUROPESIP labs to install HCL DX Compose CF238 from scratch on Kubernetes (base DX, "
             "LDAP, PostgreSQL, IQ with OpenRouter, custom MCP and search with OpenSearch) are published "
             f"at {LABS_REPO}, in English and Spanish. Every lab has its guide and ready-to-run scripts, "
             "and an optional configuration wizard."),
    "contact": f"For more information about EUROPESIP and its services: {WEB}. Support: soporte@europesip.com.",
    "iq": "At EUROPESIP, IQ uses LiteLLM with Claude through OpenRouter. LiteLLM is not supplied by HCL: we install it ourselves.",
}
# Appended to every answer: the model tends to fill in with data we did not give it
# ("official partner", made-up services...). We ask it to stick to what the tool returns.
STICK = ("\n\n[Instruction for the assistant: answer using only this EUROPESIP information; "
         "do not add services, certifications or data that do not appear here. For any other "
         f"detail, refer to {WEB}.]")

# Words the model may use to ask for each topic (English and Spanish). ORDER matters: the most
# specific topics first ("HCL labs" contains "hcl").
ALIASES = {
    "sovereignty": ["sovereign", "soberan"],
    "labs": ["lab", "compose", "install", "repo", "github", "course", "curso", "poc"],
    "support": ["support", "soporte", "hours", "horario"],
    "iq": ["litellm", "openrouter"],
    "ai": ["intelligence", "inteligencia", "artificial", "tool", "herramienta"],
    "contact": ["contact", "web", "page", "pagina", "página"],
    "services": ["service", "servicio", "company", "empresa", "who", "quien", "quién",
                 "europesip", "portal", "domino", "hcl", "ibm"],
}
# Exact short topics that would match too much as substrings
EXACT = {"ia": "ai", "ai": "ai", "soberania": "sovereignty", "soberanía": "sovereignty"}

mcp = FastMCP(
    "europesip-kb",
    host="0.0.0.0",
    port=int(os.getenv("PORT", "3000")),
    stateless_http=True,       # like the HCL MCP: no sessions, GET /mcp -> 405
    json_response=True,
    # Lab: no Host header validation (the Integrator calls it by the Service name)
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)

@mcp.tool()
def europesip_services() -> str:
    """Describes EUROPESIP and the services it offers (company specialised in HCL and IBM
    products: HCL DX portals, HCL Domino, artificial intelligence, digital sovereignty). Use it
    when the user asks who EUROPESIP is, what it does or which services it offers."""
    log.info("TOOL europesip_services")
    return SERVICES + STICK

@mcp.tool()
def europesip_faq(topic: str) -> str:
    """Looks up the EUROPESIP knowledge base. Use it when the user asks about EUROPESIP support
    (hours), its AI experience, digital sovereignty, its HCL DX Compose installation labs, its
    website or how to get in touch. Topics: support, services, ai, sovereignty, labs, contact, iq."""
    log.info("TOOL europesip_faq topic=%r", topic)
    t = topic.strip().lower()
    if t in FAQ:                                   # the exact topic
        return FAQ[t] + STICK
    if t in EXACT:
        return FAQ[EXACT[t]] + STICK
    for key, words in ALIASES.items():             # otherwise, by keywords
        if any(w in t for w in words):
            return FAQ[key] + STICK
    return "There is no information about that topic. Available topics: " + ", ".join(FAQ)

@mcp.tool(name="figma_web_to_dx", title="figma&web-to-dx")
def figma_web_to_dx(source: str = "") -> str:
    """figma&web-to-dx: designs web pages or HCL DX WCM / Blueprint components from a Figma
    design, a screenshot or the URL of an external site. Use it when the user wants to create a
    DX component, template or page from a design, an image or a website.
    Parameter source: the Figma, screenshot or site URL (optional)."""
    log.info("TOOL figma_web_to_dx source=%r", source[:200])
    return ("EUROPESIP has an MCP tool, figma&web-to-dx, that integrates with HCL DX IQ to make "
            "building Blueprint components easier and faster from simple Figma URLs, website "
            f"screenshots or site URLs. For more information, contact EUROPESIP: {WEB}." + STICK)

@mcp.tool()
def europesip_echo(text: str) -> str:
    """Diagnostic tool: returns the received text with a prefix.
    Use it only if the user explicitly asks to test the EUROPESIP echo."""
    log.info("TOOL europesip_echo")
    return f"[europesip-mcp] {text}"

@mcp.custom_route("/probe/ready", methods=["GET"])
async def probe_ready(request: Request) -> PlainTextResponse:
    """The IQ Integrator calls /probe/ready before asking for the tools (as with the HCL MCP)."""
    return PlainTextResponse("OK")

app = mcp.streamable_http_app()

class LogRequests:
    """ASGI middleware: logs method, path and header/cookie names (no values)."""
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
