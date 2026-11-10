# showroom-lab · the files of the "Deploy HCL DX Compose in Minutes" webinar

These are the exact files used in the webinar recording, so you can read every values file, secret layout and command
that appears on screen **without running the configuration wizard**.

> **You do not need these files to install DX Compose.** Everything shown in the webinar can be done by following the
> official HCL documentation: <https://help.hcl-software.com/digital-experience/dx-compose/CF239/>.
> This folder is a reference for what we used, not a required tool.

## What is here

| Folder | Content |
|---|---|
| `lab-base/` | Namespaces, the base DX values (`custom-values.yaml`), the Ingress and the DX secrets |
| `lab-ldap/` | OpenLDAP values, the demo users (`demo-users.ldif`), the bind secret, the **basic** LDAP layer (`custom-values.ldap-basic.yaml`) and the **complete** one with configuration overrides (`custom-values.ldap.yaml`: sign in by e-mail, preferred language, LDAPS with the corporate CAs), the XMLAccess request for the admin role and an **example** for a corporate Active Directory (`example-active-directory.yaml`, not applied) |
| `lab-bbdd/` | The PostgreSQL cluster (CloudNativePG, SSL only), its secrets and the Web Engine database properties (`dx_dbdomain.properties`, JDBC over SSL with `sslmode=verify-full`) |
| `lab-iq/` | LiteLLM and HCL DX IQ values |
| `lab-search/` | HCL DX Search (OpenSearch) values |
| `internals-ca/` | Explains the corporate CAs (directory and databases) that DX must trust. The certificates themselves are created when the environment is prepared |
| `prep-pki/` | The `openssl` extension files used to sign the server certificates during the preparation |
| `prepare.sh`, `demo.sh`, `RUNBOOK.md` | How we prepared the environment and ran the steps of the session |

## What is NOT here

- **Credentials.** Every password, token, key and password hash is replaced by `<REDACTED>`. Use your own values.
- **`setup-postgres-dx.sql`.** The PostgreSQL table script is HCL early-release material; ask HCL for it.
- **HCL charts and images.** Use your own HCL Harbor account (hclcr.io).
- **Keys and certificates.** They are generated when the environment is prepared.

Host names (`*.apps.promox.europesip-lab.com`) belong to our lab cluster: replace them with yours.

These files are updated with every new version of the webinar.
