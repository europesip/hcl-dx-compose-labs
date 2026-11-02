"""Lab 3B · EUROPESIP custom MCP Server for HCL DX IQ.

An MCP Server is a service that publishes "tools" (functions with a name, a description and
parameters) that the LLM can decide to call. This one exposes five, over "streamable" HTTP at /mcp
(the same transport as the HCL MCP Server):
  - europesip_services(): who EUROPESIP is and which services it offers.
  - europesip_faq(topic): support, AI, digital sovereignty, labs, contact...
    Information the model cannot know by itself.
  - figma_web_to_dx(source) -> shown as "figma&web-to-dx": presents the EUROPESIP tool that
    generates WCM / Blueprint components from Figma, screenshots or URLs.
  - europesip_whoami(): who the user asking IQ is. It uses the user's own DX session: the IQ
    Integrator forwards the DX session cookies (LtpaToken2...) on every tools/call, and the tool
    calls DX with them, so it only sees what that user is allowed to see.
  - europesip_echo(text): diagnostics.

Technical names only use [a-zA-Z0-9_-] (required by IQ/Claude); the display name goes in "title".
The answers are in English; IQ translates them to the user's language when it replies.
Every request is logged: method, path and the NAMES of headers and cookies (never their values),
to see what the IQ Integrator sends. Official MCP SDK for Python (FastMCP).
"""
import logging, os, ssl, urllib.error, urllib.request
import xml.etree.ElementTree as ET
import uvicorn
from starlette.requests import Request
from starlette.responses import PlainTextResponse
from mcp.server.fastmcp import Context, FastMCP
from mcp.server.transport_security import TransportSecuritySettings

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("europesip-mcp")

WEB = "https://www.europesip.com"
LABS_REPO = "https://github.com/europesip/hcl-dx-compose-labs"
# DX entry point inside the cluster (the DX HAProxy service), set in europesip-mcp.yaml
DX_URL = os.getenv("DX_URL", "https://dx-deployment-haproxy.dx-demo.svc.cluster.local").rstrip("/")

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

# DX User Management REST API: profile of the user that owns the session
PROFILE_PATH = "/wps/mycontenthandler/um/secure/currentuser/profile?expandRefs=true"
UM = "{http://www.ibm.com/xmlns/prod/websphere/um.xsd}"
SHOW = ["uid", "cn", "givenName", "sn", "displayName", "mail", "ibm-primaryEmail", "ibm-jobTitle"]   # never "password"
TLS = ssl._create_unverified_context()   # lab: the DX HAProxy serves a self-signed certificate

@mcp.tool()
def europesip_whoami(ctx: Context) -> str:
    """Tells who the current DX user is (the person asking), using their own DX session: user id,
    name and distinguished name. Use it when the user asks who they are, which user they are logged
    in as, or what DX knows about them."""
    request = ctx.request_context.request
    token = request.cookies.get("LtpaToken2") if request is not None else None
    log.info("TOOL europesip_whoami session=%s", "yes" if token else "no")   # never log the token
    if not token:
        return "No DX session was received with this call, so the current user cannot be identified."
    req = urllib.request.Request(DX_URL + PROFILE_PATH, headers={"Cookie": "LtpaToken2=" + token})
    try:
        with urllib.request.urlopen(req, context=TLS, timeout=10) as r:   # follows DX's /!ut/p/digest redirect
            root = ET.fromstring(r.read())
    except (urllib.error.URLError, ET.ParseError) as e:
        log.warning("europesip_whoami: DX profile call failed: %s", e)
        return "DX did not return the profile of the current user (the session may have expired)."
    dn, found = "", {}
    for el in root.iter():
        if el.tag == UM + "profile":
            dn = el.get("identifier", "")
        elif el.tag == UM + "attribute" and el.get("name") in SHOW:
            values = [v.text for v in el if v.tag == UM + "attributeValue" and v.text]
            if values:
                found[el.get("name")] = ", ".join(values)
    if not dn and not found:
        return "DX did not return the profile of the current user."
    lines = [f"- {k}: {found[k]}" for k in SHOW if k in found]
    return ("The user asking is identified by their own DX session (LtpaToken2):\n"
            f"- distinguished name: {dn}\n" + "\n".join(lines))

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
