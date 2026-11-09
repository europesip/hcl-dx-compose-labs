#!/usr/bin/env bash
# scripts/github-labels.sh · creates (or updates) the labels of the work model described in docs/workflow.md.
# Usage: scripts/github-labels.sh [owner/repo]   (default: europesip/hcl-dx-compose-labs). Needs gh with repo scope.
set -euo pipefail
R="${1:-europesip/hcl-dx-compose-labs}"
l(){ gh label create "$1" -R "$R" --color "$2" --description "$3" --force; }
# Type
l bug            CF222E "Something does not behave as it should"
l tech-debt      E36209 "A shortcut taken on purpose, to be paid back"
l enhancement    1A7F37 "A new capability, option or use case"
l blocked        6F42C1 "Depends on another task or on something external"
l documentation  0075CA "Documentation or architecture"
# Area
l area:lab0-1      BF8700 "Area: Lab 0 (PoC on WSL) and Lab 1 (DX base, Script Apps)"
l area:lab2        0969DA "Area: Lab 2 (LDAP and PostgreSQL)"
l area:lab3        BF3989 "Area: Lab 3 (IQ, LiteLLM, MCP)"
l area:lab4-5      0E8A8A "Area: Lab 4 (Search) and Lab 5 (ÓRBITA)"
l area:tooling     5B6CFF "Area: common scripts, tools, charts, webinar"
l hcl-docs         FF9900 "Caused by HCL documentation or product behaviour (see issues.md)"
# Priority
l P1 B60205 "High priority"
l P2 FBCA04 "Medium priority"
l P3 A2EEEF "Low priority"
