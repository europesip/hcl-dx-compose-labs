# Lab 1B · Script Application de ejemplo, desplegada con Helm *(opcional)*

[English](GUIDE.md) · **Español**

En **DX Compose**, los portlets Java propios necesitan el *Java Transition Module*, que se licencia
aparte: la forma nativa de construir aplicaciones propias es la **Script Application**, HTML,
JavaScript y CSS guardados en WCM. HCL despliega las Script Applications con su herramienta de línea
de comandos, DXClient. Este lab despliega una **con un chart de Helm**, como el resto de la
plataforma: sin DXClient ni herramientas de desarrollo en tu equipo, solo `helm`.

La app es **Hello DX**, una pequeña aplicación React de EUROPESIP. Muestra dos integraciones con las
API REST de DX, **como el usuario que ha iniciado sesión**: quién ha iniciado sesión y qué
bibliotecas de WCM puede leer. Código, chart y cómo funciona:
[github.com/europesip/hcl-dx-scriptapp-helm](https://github.com/europesip/hcl-dx-scriptapp-helm).

Solo necesita el **Lab 1**. ⏱ ~1 min.

```
helm upgrade --install hello-dx oci://ghcr.io/europesip/charts/hcl-dx-scriptapp
   └─ Job (tras cada install y upgrade)
        ├─ imagen del bundle ─► la app compilada (index.html, assets/)
        └─ DXClient de HCL   ─► dxclient deploy-scriptapplication push ─► WCM (Script Application Library)
```

## Paso 1 · Aceptar la licencia de DXClient

DXClient pide aceptar su licencia (una licencia de HCL para programas sin garantía). Léela:

```bash
kubectl -n "$SHARED_NS" run dxclient-license --rm -i --restart=Never \
  --image="$DXCLIENT_IMAGE" --command -- /dxclient/bin/dxclient accept-license
```

y, para aceptarla, pon en `env.sh`:

```bash
export DXCLIENT_ACCEPT_LICENSE=yes
```

## Paso 2 · Desplegar la app

```bash
lab1b-scriptapp/01-scriptapp-install.sh
```

Crea dos secrets en `dx-shared` e instala el chart:

- `scriptapp-dx`: el usuario de DX que sube la app. En el lab, `wpsadmin`; en un proyecto real, un
  usuario técnico con acceso de Editor a la Script Application Library.
- `scriptapp-dx-ca`: la CA del certificado de DX. El certificado del lab es autofirmado, así que es
  su propia CA (si no, DXClient, que es una herramienta Node.js, lo rechaza).

El log del Job termina con `OK: 'europesip-hello-dx' is in WCM (content ID ...)`.

## Paso 3 · Añadirla a una página (una vez)

En DX, edita una página, añade un componente, *Script Applications* → **Hello DX**, y publica. Cada
`helm upgrade` posterior actualiza el mismo elemento de WCM, así que todas las páginas que la usan
muestran la versión nueva.

## Comprobar

```bash
lab1b-scriptapp/99-verify.sh
```

## Conviene saber

- **Un push publica al momento**, sin flujo de trabajo. Para revisar los cambios antes, sube a un
  proyecto de WCM (`--set dx.projectContext=...`).
- **WCM guarda cada fichero en un elemento de como máximo 5.000.000 bytes**: el Job rechaza los
  ficheros de más de 4,5 MB antes de tocar DX.
- **Desinstalar el chart no borra la app de WCM** (puede haber páginas que la usen): el repositorio
  del chart explica cómo quitarla.
