"""EUROPESIP custom MCP Server for HCL DX IQ: a skeleton to build your own.

WHAT THIS IS
  An example, not a product. It shows how to extend HCL DX IQ with your own tools through a custom
  MCP Server, next to the MCP Server that HCL supplies. Copy it, replace the EUROPESIP tools with
  your own and you have the base of your own server. It is used in Lab 3B of
  https://github.com/europesip/hcl-dx-compose-labs.

HOW IQ USES IT
  An MCP Server publishes "tools": functions with a name, a description and typed parameters. When
  the IQ Integrator starts, it asks every server in its list for its tools (tools/list). On every
  question, the LLM reads the descriptions and decides whether to call one (tools/call); IQ then
  writes the answer with what the tool returned. The transport is "streamable" HTTP at POST /mcp,
  without sessions, the same as the HCL MCP Server.

WHAT THE FIVE TOOLS SHOW
  - europesip_services()       a fixed answer: the simplest possible tool.
  - europesip_faq(topic)       a tool with a parameter, looking up a small knowledge base.
  - figma_web_to_dx(source)    a technical name different from the display name ("figma&web-to-dx").
  - europesip_whoami()         a tool that calls DX AS THE USER ASKING: the Integrator forwards the
                               user's DX session cookies (LtpaToken2...) on every tools/call.
  - europesip_echo(text)       diagnostics.

ADDING YOUR OWN TOOL
  Write a Python function and decorate it with @mcp.tool(). The SDK builds the tool from it:
    - the function name is the tool name: only [a-zA-Z0-9_-] (required by IQ / Claude);
    - the docstring is the description: it is all the LLM reads to decide when to use the tool,
      and it travels in every request, so keep it short and precise;
    - the type hints are the parameter schema;
    - the returned string is what the LLM receives.
  Then rebuild the image and restart the IQ Integrator, which only lists the tools when it starts.

Every request is logged: method, path and the NAMES of headers and cookies (never their values),
to see what the IQ Integrator sends. Official MCP SDK for Python (FastMCP). The answers are in
English; IQ translates them to the user's language when it replies.
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

# ---------------------------------------------------------------------------------------------
# Configuration: environment variables, set in the Kubernetes Deployment (europesip-mcp.yaml).
# Add yours here (URLs of your APIs, database connection...); secrets come from a Secret.
# ---------------------------------------------------------------------------------------------
WEB = "https://www.europesip.com"
LABS_REPO = "https://github.com/europesip/hcl-dx-compose-labs"
# DX entry point inside the cluster (the DX HAProxy service), set in europesip-mcp.yaml
DX_URL = os.getenv("DX_URL", "https://dx-deployment-haproxy.dx-demo.svc.cluster.local").rstrip("/")

# ---------------------------------------------------------------------------------------------
# Knowledge base. In this example it is written in the code; in your own server it could be read
# from a database, from DX WCM content or from any REST API (see the README).
# ---------------------------------------------------------------------------------------------
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
    "labs": ("The EUROPESIP labs to install HCL DX Compose CF239 from scratch on Kubernetes (base DX, "
             "LDAP, PostgreSQL, IQ with OpenRouter, custom MCP, search with OpenSearch and the ÓRBITA "
             "intranet application) are published "
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

# ---------------------------------------------------------------------------------------------
# The MCP Server. These settings are what the IQ Integrator needs; keep them in your own server.
# ---------------------------------------------------------------------------------------------
mcp = FastMCP(
    "europesip-kb",
    host="0.0.0.0",
    port=int(os.getenv("PORT", "3000")),
    stateless_http=True,       # like the HCL MCP: no sessions, GET /mcp -> 405
    json_response=True,
    # Lab: no Host header validation (the Integrator calls it by the Service name)
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)

# ---------------------------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------------------------

# Tool 1 · The simplest possible tool: no parameters, a fixed answer. The LLM calls it when the
# question matches its description (who EUROPESIP is, what it does...).
@mcp.tool()
def europesip_services() -> str:
    """Describes EUROPESIP and the services it offers (company specialised in HCL and IBM
    products: HCL DX portals, HCL Domino, artificial intelligence, digital sovereignty). Use it
    when the user asks who EUROPESIP is, what it does or which services it offers."""
    log.info("TOOL europesip_services")
    return SERVICES + STICK

# Tool 2 · A tool with a parameter: the LLM fills in "topic" from the question. As the model may
# not use exactly our topic names, it also matches keywords. This is the tool to replace with a
# query to your own data (database, WCM, REST API).
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

# Tool 3 · Technical name vs display name. IQ / Claude only accept tool names with
# [a-zA-Z0-9_-], so "figma&web-to-dx" goes in "title" and in the description. Today it only
# presents the EUROPESIP tool; a real version would start the conversion and return a task id.
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

# Tool 4 · Acting as the user asking. On every tools/call the IQ Integrator forwards the DX session
# cookies of that user. The tool calls the DX User Management REST API with the LtpaToken2 cookie,
# so DX answers with THAT user's identity and permissions: no administrative account is needed.
# The same pattern lets your own tools read or change DX content (WCM, DAM...) as the user.
PROFILE_PATH = "/wps/mycontenthandler/um/secure/currentuser/profile?expandRefs=true"
UM = "{http://www.ibm.com/xmlns/prod/websphere/um.xsd}"
SHOW = ["uid", "cn", "givenName", "sn", "displayName", "mail", "ibm-primaryEmail", "ibm-jobTitle"]   # never "password"
TLS = ssl._create_unverified_context()   # lab: the DX HAProxy serves a self-signed certificate

@mcp.tool()
def europesip_whoami(ctx: Context) -> str:
    """Tells who the current DX user is (the person asking), using their own DX session: user id,
    name and distinguished name. Use it when the user asks who they are, which user they are logged
    in as, or what DX knows about them."""
    # The HTTP request of the tools/call, with the cookies forwarded by the Integrator
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
    # DX answers with an XML profile: keep the distinguished name and the allowed attributes only
    # (the profile also includes the LDAP password hash, which must never be returned)
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

# Tool 5 · Diagnostics: checks the whole path IQ -> Integrator -> this server without the LLM
# having to interpret anything. The description limits it to explicit requests.
@mcp.tool()
def europesip_echo(text: str) -> str:
    """Diagnostic tool: returns the received text with a prefix.
    Use it only if the user explicitly asks to test the EUROPESIP echo."""
    log.info("TOOL europesip_echo")
    return f"[europesip-mcp] {text}"

# ---------------------------------------------------------------------------------------------
# HTTP plumbing: readiness probe, request log and start-up. Keep it as is in your own server.
# ---------------------------------------------------------------------------------------------
@mcp.custom_route("/probe/ready", methods=["GET"])
async def probe_ready(request: Request) -> PlainTextResponse:
    """The IQ Integrator calls /probe/ready before asking for the tools (as with the HCL MCP);
    Kubernetes uses it as the readiness probe too."""
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
