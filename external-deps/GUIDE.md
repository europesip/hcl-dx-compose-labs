# External dependencies

**English** · [Español](GUIDE.es.md)

Four pieces that are **not HCL software** and that some labs use. They go in the shared namespace
(`dx-shared`), apart from DX, and they are installed **first, before Lab 1**: with them already in
place, the labs only connect DX to them, and a demo goes faster.

| Dependency | Script | Used by | ⏱ |
|---|---|---|---|
| **OpenLDAP** with demo users and groups | [01-openldap.sh](01-openldap.sh) | Lab 2A | ~2 min |
| **PostgreSQL 18** (CloudNativePG) | [02-postgres.sh](02-postgres.sh) | Lab 3 appendix (IQ sessions), your own uses | ~3 min |
| **LiteLLM** (proxy to OpenRouter) | [03-litellm.sh](03-litellm.sh) | Lab 3A (IQ) | ~1 min |
| **EUROPESIP MCP Server** | [04-mcp.sh](04-mcp.sh) | Lab 3B | ~1 min |

Install only what the labs you plan need. Each script reuses the steps of its lab, so the result
is the same as doing them inside the lab: the lab guides say which steps you can then skip.

## Before you start

The two namespaces must exist (the same script as Lab 1 step 2, harmless if run again):

```bash
source ./env.sh
common/00-check-prereqs.sh
common/01-namespaces.sh
```

## Install them

```bash
external-deps/01-openldap.sh     # OpenLDAP + test (Lab 2A steps 1-2)
external-deps/02-postgres.sh     # CNPG operator, users and cluster (Lab 2B steps 1-3)
external-deps/03-litellm.sh      # secrets, LiteLLM and a test call (Lab 3A steps 1-3); needs OPENROUTER_API_KEY
external-deps/04-mcp.sh          # EUROPESIP MCP Server + test (Lab 3B steps 1-2)
external-deps/99-verify.sh       # what is installed
```

## PostgreSQL and the Web Engine database

`02-postgres.sh` creates the cluster with the `dx_core` database **empty**, unless you put first in
`lab2-ldap-postgres/b-postgres/` the table creation script that HCL gives you
(`setup-postgres-dx.sql`, **not supplied with the labs yet** because it has not been validated):
then the cluster runs it when it is created and Lab 2B can move the Web Engine to PostgreSQL.
Without it, the Web Engine keeps **Derby** (the internal database of the product, the default) or
uses an existing **Oracle** (Lab 2 enterprise branch), and PostgreSQL serves other advanced options,
such as the IQ chat sessions (Lab 3 appendix).

## If you do not install one

- **OpenLDAP:** Lab 2A connects DX to an existing **Active Directory** instead
  ([enterprise branch](../lab2-ldap-postgres/GUIDE-enterprise.md)), or you skip Lab 2A.
- **PostgreSQL:** the IQ sessions appendix is not available (IQ keeps its sessions in memory).
- **LiteLLM:** Lab 3A installs it in its own steps 1-3 (the lab always installs LiteLLM).
- **MCP Server:** Lab 3B deploys it in its own steps 1-2.

## Fast demo

With the dependencies in place, `common/demo-fast.sh` installs DX **once**, already connected to
its directory, then IQ and search, and enables both with **one single** DX upgrade (about 15
minutes less than the labs one by one). What it installs comes from `DEMO_DEPS` and `DEMO_LABS` in
`env.sh` (the configuration wizard fills them in):

```bash
DEMO_DEPS="openldap postgres litellm mcp" DEMO_LABS="1b 2a-openldap 3a 3b iqdb 4" common/demo-fast.sh
```

Next: [Lab 1 · Base DX](../lab1-dx-base/GUIDE.md).
