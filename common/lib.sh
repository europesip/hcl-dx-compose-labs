#!/usr/bin/env bash
# Funciones comunes. Lo cargan todos los scripts:  source "$(dirname "$0")/../common/lib.sh"

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$_LIB_DIR/.." && pwd)}"

# Carga env.sh si el usuario no lo ha cargado ya
if [[ -z "${DX_ENV_LOADED:-}" ]]; then
  if [[ -f "$REPO_ROOT/env.sh" ]]; then
    # shellcheck disable=SC1091
    source "$REPO_ROOT/env.sh"
  else
    echo "❌ No existe $REPO_ROOT/env.sh. Créalo con:  cp env.example.sh env.sh  y edítalo." >&2
    exit 1
  fi
fi

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[1;33mAVISO\033[0m %s\n' "$*"; }
fail() { printf '  \033[1;31mFALLO\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

# require_vars VAR1 VAR2 ...  -> aborta si alguna está vacía (sin mostrar su valor)
require_vars() {
  local v missing=()
  for v in "$@"; do [[ -n "${!v:-}" ]] || missing+=("$v"); done
  ((${#missing[@]} == 0)) || die "Faltan variables en env.sh: ${missing[*]}"
}

# require_cmd cmd1 cmd2 ...
require_cmd() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "Falta la herramienta '$c' en tu estación de trabajo"; done
}

# apply_secret <ns> <kubectl create secret ... args>  -> crea o actualiza de forma idempotente
apply_secret() {
  local ns="$1"; shift
  kubectl -n "$ns" create secret "$@" --dry-run=client -o yaml | kubectl apply -f -
}

# render <plantilla> '<$VAR1 $VAR2>'  -> sustituye SOLO las variables indicadas y escribe en stdout
render() { envsubst "$2" < "$1"; }

is_openshift() { [[ "$PLATFORM" == "openshift" ]]; }

# Espera de Helm hasta que todo esté Ready. Helm 4 cambió el comportamiento de "--wait": por
# defecto usa la estrategia "watcher", que ABORTA en cuanto un pod aparece como fallido. DX tiene
# fallos normales al arrancar (DAM reintenta hasta que su PostgreSQL está listo), así que con Helm 4
# usamos "--wait=legacy", que, como Helm 3, espera hasta el --timeout a que todo quede Ready.
if helm version --short 2>/dev/null | grep -q '^v3'; then HELM_WAIT="--wait"; else HELM_WAIT="--wait=legacy"; fi
