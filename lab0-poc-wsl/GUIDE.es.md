# Lab 0 · PoC en tu PC: k3s de un nodo en WSL2

[English](GUIDE.md) · **Español**

> ⚠️ **Esto es un entorno de PoC, no una instalación de referencia.** Su único objetivo es poder
> **comprobar, de la forma más sencilla posible, los pasos de una instalación real** de HCL DX
> Compose cuando no se tiene acceso a un clúster Kubernetes. Para conseguirlo en un solo PC **ha
> habido que "trucar" el sistema**:
>
> - la StorageClass RWX (`dx-deploy-rwx`) se **simula** con un volumen `hostPath` creado a mano,
>   porque el almacenamiento local de k3s no admite volúmenes compartidos;
> - las **reservas de recursos** de los charts de HCL se **rebajan** (capa `DX_POC=1`) para que
>   todo quepa en la memoria de WSL;
> - todo corre en **un único nodo**, sin alta disponibilidad, con el almacenamiento en el disco
>   del PC y el DNS resuelto con `nip.io`.
>
> Nada de esto es válido para producción ni está soportado por HCL. En un entorno real, las
> StorageClasses las proporciona el almacenamiento corporativo o de la nube (NFS, Ceph/ODF,
> Longhorn, discos gestionados...) y los recursos se dimensionan para la carga real.
>
> Aunque al terminar se obtiene una instalación **funcional**, ni este Lab 0 ni los labs que se
> ejecutan sobre él incluyen el *tuning* ni la parametrización de un entorno productivo, que se han
> omitido para no complicarlos. Para un proyecto real, recomendamos contar siempre con un
> **partner de HCL** o con los **servicios especializados de HCL**.

**Para quién:** quien **no tenga forma de acceder a un clúster Kubernetes**, ni en local ni en la
nube, con las dos StorageClasses que piden los labs ([requisitos](../docs/requirements.es.md)), y quiera
hacerlos en su propio PC con Windows. Si tienes acceso a un clúster (k3s, RKE2, OpenShift, EKS,
AKS, GKE...), usa ese y sáltate este lab.

**Qué se monta:** una distribución de WSL2 nueva con **k3s**, la misma distribución de Kubernetes
del clúster de referencia de los labs (de Rancher/SUSE), en **un solo nodo** que hace de master y de worker, con:

- las StorageClasses `dx-deploy-rwo` y `dx-deploy-rwx` que esperan los labs,
- ingress-nginx, para entrar en DX desde el navegador de Windows,
- y una capa de recursos reducidos para que los cuatro labs quepan en un PC.

Después, los Labs 1 a 4 se hacen **exactamente igual** que en el clúster de referencia.

**⏱ Tiempo estimado:** ~10 minutos para preparar la POC (pasos 1 a 5) y ~35 minutos de ejecución
para los cuatro labs. Detalle en *Tiempos, memoria y disco medidos*, al final.

---

## ¿Por qué WSL2 + k3s y no Docker Desktop o Multipass?

| | **WSL2 + k3s** (esta guía) | Docker Desktop (Kubernetes) | Multipass + k3s |
|---|---|---|---|
| Kubernetes | **k3s, el mismo que el clúster de referencia** | kubeadm/kind de Docker | k3s |
| Windows Home | **Sí** | Sí | Solo con VirtualBox (Home no tiene Hyper-V) |
| Licencia | Gratis | **De pago en empresas** de más de 250 empleados o 10 M$ | Gratis |
| Cambios en los labs | **Ninguno** | StorageClasses e Ingress distintos | Ninguno, pero otra red y otro DNS |
| Acceso desde Windows | `localhost` | `localhost` | IP de la VM |

## Requisitos del PC

| | Mínimo | Recomendado |
|---|---|---|
| Windows | 10 (22H2) u 11, Home o Pro | 11 |
| RAM del PC | 32 GB: WSL toma por defecto la mitad, **~16 GB**. Los cuatro labs **pueden funcionar, pero muy justos** | **24 GB para WSL** (`memory=24GB` en `.wslconfig`, ver paso 1): requiere un PC de 32 GB o más |
| CPU | 8 núcleos | 12-16 |
| Disco libre | 40 GB (imágenes ~20 GB + volúmenes ~3 GB) | 60 GB |
| WSL | WSL2 actualizado (`wsl --update`) | 2.4 o superior (permite `--name`) |

> **Las distros de WSL2 comparten una sola VM**: mismo kernel, misma red y **misma memoria**.
> Una distro nueva separa ficheros, usuarios, servicios y `kubeconfig` (no toca tus otras distros),
> pero la memoria se reparte: durante la POC, no tengas otras cargas pesadas en WSL.

---

## Paso 1 · Crear la distro de WSL (PowerShell de Windows)

```powershell
wsl --update
wsl --install Ubuntu-24.04 --name dx-poc
```

Pide un usuario y una contraseña para Linux (en los labs: `dxuser` / `EuropeS1P`). Al terminar
queda dentro de la distro. Para volver a entrar más adelante: `wsl -d dx-poc`.

Ubuntu 24.04 en WSL ya trae **systemd** activado (`/etc/wsl.conf` → `[boot] systemd=true`), que k3s
necesita, y `vm.max_map_count` suficiente para OpenSearch (1048576).

> **Memoria: se recomiendan 24 GB para WSL.** WSL usa por defecto la mitad de la RAM del PC (en
> un PC de 32 GB, unos 16 GB). Con los cuatro labs en marcha medimos **12,6 GiB de uso real** de
> los ~15 GiB de la VM: **puede funcionar con 16 GB, pero muy justo** (cualquier otra carga en WSL
> o un pico de uso puede dejar pods sin memoria). Para darle 24 GB, crea
> `%UserProfile%\.wslconfig` en Windows:
> ```ini
> [wsl2]
> memory=24GB
> ```
> y aplica con `wsl --shutdown` (apaga **todas** las distros de WSL). Afecta a todas tus distros,
> pero WSL solo ocupa la memoria que usa.

## Paso 2 · Instalar k3s y Helm (dentro de `dx-poc`)

Con tu usuario normal (**sin** `sudo` delante: los comandos lo llevan donde hace falta) y desde
tu home:

```bash
cd ~
```

**k3s** de un nodo, la misma versión que el clúster de referencia, sin Traefik (usaremos ingress-nginx):

```bash
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION=v1.35.5+k3s1 sh -s - --disable traefik --write-kubeconfig-mode 644
```

**kubeconfig** para tu usuario (k3s trae `kubectl`):

```bash
mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown $USER:$USER ~/.kube/config && chmod 600 ~/.kube/config
```

**Helm**:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Comprobar:

```bash
kubectl get nodes && helm version --short
```

Debe salir un nodo `Ready` (con el nombre de tu PC) y Helm `v3.x`.

> Avisos normales durante la instalación de k3s: `Host iptables-save/iptables-restore tools not
> found` (k3s usa las suyas) y `Skipping installation of SELinux RPM`.

## Paso 3 · Clonar los labs y preparar `env.sh`

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
cp env.example.sh env.sh
```

(o genera `env.sh` con el [asistente de configuración](https://europesip.github.io/hcl-dx-compose-labs/?lang=es)
eligiendo la plataforma *PoC en WSL2*: ya rellena estos valores.)

En `env.sh`, además de las credenciales de `hclcr.io` (y la clave de OpenRouter para el Lab 3):

```bash
export DX_HOST="${DX_HOST:-dx-demo.127.0.0.1.nip.io}"   # nip.io: resuelve a 127.0.0.1, sin tocar DNS ni hosts
export DX_POC="${DX_POC:-1}"                            # capa de recursos reducidos de este Lab 0
```

- **`nip.io`** es un DNS público que devuelve la IP escrita en el nombre:
  `dx-demo.127.0.0.1.nip.io` → `127.0.0.1`, tanto en WSL como en Windows.
- **`DX_POC=1`** añade al final de cada `helm upgrade` las capas
  [custom-values.poc.yaml](custom-values.poc.yaml) (DX) y
  [custom-search-values.poc.yaml](custom-search-values.poc.yaml) (búsqueda), ver paso 6.

## Paso 4 · StorageClasses

```bash
lab0-poc-wsl/01-storage.sh
```

| StorageClass | Cómo se implementa en la POC | Lo usan |
|---|---|---|
| `dx-deploy-rwo` | El aprovisionador **`local-path`** que trae k3s: un directorio del disco por cada PVC | Web Engine, Persistence Node, License Manager, PostgreSQL, OpenLDAP, OpenSearch |
| `dx-deploy-rwx` | **Estática** (`kubernetes.io/no-provisioner`) + un PersistentVolume `hostPath` creado por el script (`dx-poc-dam-binaries`, 10 GiB) | Binarios de DAM |

**Por qué `dx-deploy-rwx` es estática.** El chart de DX pide **ReadWriteMany** para los binarios de
DAM (fijo en la plantilla, no se puede cambiar por values), y el `local-path` de k3s lo rechaza:
*"NodePath only supports ReadWriteOnce"*. En un solo nodo, un volumen `hostPath` **sí** es RWX de
verdad (todos los pods ven el mismo disco), así que basta con crearlo a mano. Lo comprobamos con
dos pods escribiendo y leyendo el mismo fichero.

**Permisos del directorio.** Kubernetes crea el directorio `hostPath` como `root` con permisos
755, y en los volúmenes `hostPath` **no se aplica el `fsGroup`** del pod. DAM corre como
`uid 1000` / `gid 1001`, así que no podría escribir: queda en `1/2` con
`EACCES: permission denied, access '/opt/app/upload'` en su log y Helm agota el tiempo de espera.
Por eso el script deja el directorio como `1000:1001` con permisos `2775`, usando un pod efímero
(sin `sudo`).

> Al borrar DX con `common/99-cleanup.sh`, este volumen queda `Released` (no se borra solo):
> vuelve a ejecutar `lab0-poc-wsl/01-storage.sh` antes de reinstalar, y lo recrea vacío.

## Paso 5 · Ingress

```bash
lab0-poc-wsl/02-ingress.sh
```

Instala **ingress-nginx** (el mismo Ingress Controller que el clúster de referencia, así el
`ingress-dx.yaml` del Lab 1 sirve sin cambios) con `hostNetwork`: escucha directamente en los
puertos 80 y 443 de WSL, y **WSL reenvía `localhost` de Windows a WSL**, así que el navegador de
Windows llega a DX por `https://dx-demo.127.0.0.1.nip.io`.

Comprobar (debe responder 404, la página por defecto de ingress-nginx):

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/
```

> Los puertos 80 y 443 quedan ocupados en la VM de WSL, compartida por todas tus distros.

## Paso 6 · La capa de recursos reducidos (`DX_POC=1`)

Las **reservas** (*requests*) de los charts de HCL están pensadas para producción: solo el DX base
reserva ~10,4 GiB y los cuatro labs ~17 GiB, más de lo que tiene la VM de WSL (~15 GiB). Pero el
uso real en una demo es mucho menor (el Web Engine reserva 4 GiB y usa ~2,7 GiB).

La capa POC baja **solo las reservas** (lo que Kubernetes suma para decidir si un pod cabe en el
nodo) de los componentes que más reservan; los **límites** no cambian:

| Componente | Reserva por defecto | Reserva POC |
|---|---|---|
| Web Engine | 4 GiB | 3 GiB |
| Image Processor | 2 GiB | 512 MiB |
| DAM | 1,5 GiB | 1 GiB |
| Persistence Node | 1 GiB | 768 MiB |
| OpenSearch (Lab 4) | 2 GiB | 1,5 GiB |
| File Processor (Lab 4) | 2 GiB | 512 MiB |
| Search Middleware (Lab 4) | 768 MiB | 512 MiB |

Resultado: el DX base pasa de reservar **10,4 a 7,2 GiB**, y los cuatro labs de ~17 a ~11 GiB.

## Paso 7 · Los labs

A partir de aquí, sigue los Labs 1 a 4 **sin cambios**, empezando por
[Lab 1](../lab1-dx-base/GUIDE.es.md) (`common/00-check-prereqs.sh`...).

---

## Tiempos, memoria y disco medidos

Ejecución real en un portátil con Windows 11 Home, 32 GB de RAM y 16 núcleos (WSL con los ~15 GiB
por defecto), con la capa `DX_POC=1`:

| Lab | Tiempo | Nota |
|---|---|---|
| 0 · k3s + Helm (pasos 1-2) | ~3 min | Descarga de k3s y Helm |
| 0 · StorageClasses e Ingress (pasos 4-5) | ~2 min | |
| 1 · DX base | **~4 min** | Incluye la **primera descarga** de las imágenes de HCL (en paralelo, 30-50 s cada una) |
| 2A · LDAP | ~5 min | |
| 2B · PostgreSQL | ~10 min | La transferencia, ~9 min |
| 3A · IQ | ~7 min | |
| 3B · MCP propio | ~2 min | |
| 4 · OpenSearch | ~7 min | |

| Recurso, con los cuatro labs en marcha | Medido |
|---|---|
| Reservas de memoria (lo que planifica Kubernetes) | 11,4 GiB de 15,3 (74 %). Sin la capa POC serían ~17 GiB: **no cabría** |
| Uso real de memoria | **12,6 GiB (82 %)**: funciona con los ~16 GB por defecto de WSL, pero muy justo; se recomiendan 24 GB |
| Uso real de CPU | ~5 núcleos (31 % de 16) |
| Disco | ~20 GB de imágenes + ~3 GB de volúmenes |

## Problemas frecuentes de la POC

| Síntoma | Causa | Solución |
|---|---|---|
| PVC de DAM en `Pending`: *"NodePath only supports ReadWriteOnce"* | `dx-deploy-rwx` apunta al `local-path` de k3s | Usa la StorageClass estática de `storage-poc.yaml` (`lab0-poc-wsl/01-storage.sh`) |
| DAM en `1/2` y Helm agota el tiempo: `EACCES ... /opt/app/upload` en el log de DAM | El directorio `hostPath` es de `root` | `lab0-poc-wsl/01-storage.sh` lo deja como `1000:1001` (repítelo y DAM queda listo sin reiniciar) |
| Pods en `Pending` con `Insufficient memory` | Faltan reservas de memoria | `DX_POC=1` en `env.sh`, o más memoria en `.wslconfig` |
| El navegador de Windows no abre `https://dx-demo.127.0.0.1.nip.io` | ingress-nginx no escucha o WSL no reenvía `localhost` | `curl http://localhost/` dentro de WSL debe dar 404; si sí da y Windows no, revisa `localhostForwarding` en `.wslconfig` (por defecto activado) |
| `nip.io` no resuelve | Sin acceso a DNS público | Añade `127.0.0.1 dx-demo.local` al `hosts` de Windows y de WSL y usa ese nombre en `DX_HOST` |

## Desinstalar la POC

Solo los labs (DX y lo de `dx-shared`), conservando k3s:

```bash
common/99-cleanup.sh --yes && lab0-poc-wsl/01-storage.sh
```

Todo, incluida la distro (PowerShell de Windows; borra la distro entera y sus datos):

```powershell
wsl --unregister dx-poc
```
