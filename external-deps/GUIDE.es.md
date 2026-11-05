# Dependencias externas

[English](GUIDE.md) · **Español**

Cuatro piezas que **no son software de HCL** y que usan algunos labs. Van en el namespace compartido
(`dx-shared`), separadas de DX, y se instalan **primero, antes del Lab 1**: con ellas ya instaladas,
los labs solo conectan DX a ellas, y una demo va más rápida.

| Dependencia | Script | La usa | ⏱ |
|---|---|---|---|
| **OpenLDAP** con usuarios y grupos de demo | [01-openldap.sh](01-openldap.sh) | Lab 2A | ~2 min |
| **PostgreSQL 18** (CloudNativePG) | [02-postgres.sh](02-postgres.sh) | Apéndice del Lab 3 (sesiones de IQ), tus propios usos | ~3 min |
| **LiteLLM** (proxy hacia OpenRouter) | [03-litellm.sh](03-litellm.sh) | Lab 3A (IQ) | ~1 min |
| **MCP Server de EUROPESIP** | [04-mcp.sh](04-mcp.sh) | Lab 3B | ~1 min |

Instala solo lo que necesiten los labs que vas a hacer. Cada script reutiliza los pasos de su lab,
así que el resultado es el mismo que hacerlos dentro del lab: las guías de los labs dicen qué pasos
puedes saltarte después.

## Antes de empezar

Tienen que existir los dos namespaces (el mismo script que el paso 2 del Lab 1, repetirlo no tiene
efecto):

```bash
source ./env.sh
common/00-check-prereqs.sh
common/01-namespaces.sh
```

## Instalarlas

```bash
external-deps/01-openldap.sh     # OpenLDAP + prueba (Lab 2A pasos 1-2)
external-deps/02-postgres.sh     # operador CNPG, usuarios y cluster (Lab 2B pasos 1-3)
external-deps/03-litellm.sh      # secrets, LiteLLM y una llamada de prueba (Lab 3A pasos 1-3); necesita OPENROUTER_API_KEY
external-deps/04-mcp.sh          # MCP Server de EUROPESIP + prueba (Lab 3B pasos 1-2)
external-deps/99-verify.sh       # qué hay instalado
```

## PostgreSQL y la base de datos del Web Engine

`02-postgres.sh` crea el cluster con la base de datos `dx_core` **vacía**, salvo que dejes antes en
`lab2-ldap-postgres/b-postgres/` el script de creación de las tablas que te da HCL
(`setup-postgres-dx.sql`, que **aún no se suministra con los labs** porque no ha sido validado):
entonces el cluster lo ejecuta al crearse y el Lab 2B puede pasar el Web Engine a PostgreSQL. Sin
él, el Web Engine sigue con **Derby** (la base de datos interna del producto, la opción por defecto)
o usa un **Oracle** existente (rama empresarial del Lab 2), y PostgreSQL sirve para otras opciones
avanzadas, como las sesiones del chat de IQ (apéndice del Lab 3).

## Si no instalas alguna

- **OpenLDAP:** el Lab 2A conecta DX a un **Active Directory** existente en su lugar
  ([rama empresarial](../lab2-ldap-postgres/GUIDE-enterprise.es.md)), o te saltas el Lab 2A.
- **PostgreSQL:** el apéndice de sesiones de IQ no está disponible (IQ guarda sus sesiones en memoria).
- **LiteLLM:** lo instala el Lab 3A en sus pasos 1-3 (el lab instala LiteLLM siempre).
- **MCP Server:** lo despliega el Lab 3B en sus pasos 1-2.

## Demo rápida

Con las dependencias instaladas, `common/demo-fast.sh` instala DX **una sola vez**, ya conectado a su
directorio, después IQ y la búsqueda, y activa las dos con **un único** upgrade de DX (unos 15
minutos menos que los labs uno a uno). Lo que instala sale de `DEMO_DEPS` y `DEMO_LABS` en `env.sh`
(el asistente de configuración los rellena):

```bash
DEMO_DEPS="openldap postgres litellm mcp" DEMO_LABS="1b 2a-openldap 3a 3b iqdb 4" common/demo-fast.sh
```

Siguiente: [Lab 1 · DX base](../lab1-dx-base/GUIDE.es.md).
