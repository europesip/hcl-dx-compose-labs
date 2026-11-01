# Lab 0 · PoC on your PC: single-node k3s on WSL2

**English** · [Español](GUIDE.es.md)

> ⚠️ **This is a PoC environment, not a reference installation.** Its only goal is to let you
> **check, in the simplest possible way, the steps of a real installation** of HCL DX Compose when
> you have no access to a Kubernetes cluster. To achieve this on a single PC **the system had to be
> "tweaked"**:
>
> - the RWX StorageClass (`dx-deploy-rwx`) is **simulated** with a `hostPath` volume created by
>   hand, because the k3s local storage does not support shared volumes;
> - the **resource requests** of the HCL charts are **lowered** (`DX_POC=1` layer) so that
>   everything fits in the WSL memory;
> - everything runs on **a single node**, without high availability, with the storage on the PC
>   disk and DNS resolved with `nip.io`.
>
> None of this is valid for production or supported by HCL. In a real environment the
> StorageClasses come from corporate or cloud storage (NFS, Ceph/ODF, Longhorn, managed disks...)
> and resources are sized for the real load.
>
> Although you end up with a **working** installation, neither this Lab 0 nor the labs run on top
> of it include the tuning and parameterisation of a production environment, which have been left
> out to keep them simple. For a real project we always recommend working with an **HCL partner**
> or with **HCL specialised services**.

**Who it is for:** anyone who **has no way to access a Kubernetes cluster**, neither local nor in
the cloud, with the two StorageClasses the labs need ([requirements](../docs/requirements.md)), and
wants to do them on their own Windows PC. If you have access to a cluster (k3s, RKE2, OpenShift,
EKS, AKS, GKE...), use it and skip this lab.

**What gets built:** a new WSL2 distribution with **k3s**, the same Kubernetes distribution as the
reference lab cluster (from Rancher/SUSE), on **a single node** acting as master and worker, with:

- the `dx-deploy-rwo` and `dx-deploy-rwx` StorageClasses the labs expect,
- ingress-nginx, to reach DX from the Windows browser,
- and a reduced-resources layer so that the four labs fit on a PC.

After that, Labs 1 to 4 are done **exactly the same way** as on the reference cluster.

**⏱ Estimated time:** ~10 minutes to prepare the PoC (steps 1 to 5) and ~35 minutes of run time
for the four labs. Details in *Measured times, memory and disk*, at the end.

---

## Why WSL2 + k3s and not Docker Desktop or Multipass?

| | **WSL2 + k3s** (this guide) | Docker Desktop (Kubernetes) | Multipass + k3s |
|---|---|---|---|
| Kubernetes | **k3s, the same as the reference cluster** | Docker's kubeadm/kind | k3s |
| Windows Home | **Yes** | Yes | Only with VirtualBox (Home has no Hyper-V) |
| Licence | Free | **Paid in companies** with more than 250 employees or $10M | Free |
| Changes to the labs | **None** | Different StorageClasses and Ingress | None, but another network and DNS |
| Access from Windows | `localhost` | `localhost` | VM IP |

## PC requirements

| | Minimum | Recommended |
|---|---|---|
| Windows | 10 (22H2) or 11, Home or Pro | 11 |
| PC RAM | 32 GB: by default WSL takes half, **~16 GB**. The four labs **can work, but very tight** | **24 GB for WSL** (`memory=24GB` in `.wslconfig`, see step 1): needs a PC with 32 GB or more |
| CPU | 8 cores | 12-16 |
| Free disk | 40 GB (images ~20 GB + volumes ~3 GB) | 60 GB |
| WSL | Up-to-date WSL2 (`wsl --update`) | 2.4 or later (supports `--name`) |

> **WSL2 distros share a single VM**: same kernel, same network and **same memory**. A new distro
> separates files, users, services and `kubeconfig` (it does not touch your other distros), but
> memory is shared: during the PoC, do not run other heavy workloads in WSL.

---

## Step 1 · Create the WSL distro (Windows PowerShell)

```powershell
wsl --update
wsl --install Ubuntu-24.04 --name dx-poc
```

It asks for a Linux user and password (in the labs: `dxuser` / `EuropeS1P`). When it finishes you
are inside the distro. To get back in later: `wsl -d dx-poc`.

Ubuntu 24.04 on WSL already has **systemd** enabled (`/etc/wsl.conf` → `[boot] systemd=true`),
which k3s needs, and a large enough `vm.max_map_count` for OpenSearch (1048576).

> **Memory: 24 GB for WSL is recommended.** By default WSL uses half of the PC RAM (on a 32 GB PC,
> about 16 GB). With the four labs running we measured **12.6 GiB of real usage** out of the
> ~15 GiB of the VM: **it can work with 16 GB, but very tight** (any other WSL workload or a usage
> peak can leave pods without memory). To give it 24 GB, create `%UserProfile%\.wslconfig` in
> Windows:
> ```ini
> [wsl2]
> memory=24GB
> ```
> and apply it with `wsl --shutdown` (it shuts down **all** WSL distros). It affects all your
> distros, but WSL only takes the memory it uses.

## Step 2 · Install k3s and Helm (inside `dx-poc`)

With your normal user (**without** `sudo` in front: the commands use it where needed) and from
your home directory:

```bash
cd ~
```

Single-node **k3s**, the same version as the reference cluster, without Traefik (we use ingress-nginx):

```bash
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION=v1.35.5+k3s1 sh -s - --disable traefik --write-kubeconfig-mode 644
```

**kubeconfig** for your user (k3s ships `kubectl`):

```bash
mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown $USER:$USER ~/.kube/config && chmod 600 ~/.kube/config
```

**Helm**:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Check:

```bash
kubectl get nodes && helm version --short
```

You should see one `Ready` node (with your PC name) and Helm `v3.x`.

> Normal warnings during the k3s installation: `Host iptables-save/iptables-restore tools not
> found` (k3s uses its own) and `Skipping installation of SELinux RPM`.

## Step 3 · Clone the labs and prepare `env.sh`

```bash
git clone https://github.com/europesip/hcl-dx-compose-labs.git
cd hcl-dx-compose-labs
cp env.example.sh env.sh
```

(or generate `env.sh` with the [configuration wizard](https://europesip.github.io/hcl-dx-compose-labs/)
choosing the *PoC on WSL2* platform: it already fills in these values.)

In `env.sh`, besides the `hclcr.io` credentials (and the OpenRouter key for Lab 3):

```bash
export DX_HOST="${DX_HOST:-dx-demo.127.0.0.1.nip.io}"   # nip.io: resolves to 127.0.0.1, no DNS or hosts changes
export DX_POC="${DX_POC:-1}"                            # reduced-resources layer of this Lab 0
```

- **`nip.io`** is a public DNS that returns the IP written in the name:
  `dx-demo.127.0.0.1.nip.io` → `127.0.0.1`, both in WSL and in Windows.
- **`DX_POC=1`** adds at the end of every `helm upgrade` the layers
  [custom-values.poc.yaml](custom-values.poc.yaml) (DX) and
  [custom-search-values.poc.yaml](custom-search-values.poc.yaml) (search), see step 6.

## Step 4 · StorageClasses

```bash
lab0-poc-wsl/01-storage.sh
```

| StorageClass | How the PoC implements it | Used by |
|---|---|---|
| `dx-deploy-rwo` | The **`local-path`** provisioner shipped with k3s: one disk directory per PVC | Web Engine, Persistence Node, License Manager, PostgreSQL, OpenLDAP, OpenSearch |
| `dx-deploy-rwx` | **Static** (`kubernetes.io/no-provisioner`) + a `hostPath` PersistentVolume created by the script (`dx-poc-dam-binaries`, 10 GiB) | DAM binaries |

(The names come from `SC_RWO` / `SC_RWX` in `env.sh`.)

**Why `dx-deploy-rwx` is static.** The DX chart asks for **ReadWriteMany** for the DAM binaries
(fixed in the template, it cannot be changed through values), and the k3s `local-path` rejects it:
*"NodePath only supports ReadWriteOnce"*. On a single node a `hostPath` volume **really is** RWX
(every pod sees the same disk), so creating it by hand is enough. We checked it with two pods
writing and reading the same file.

**Directory permissions.** Kubernetes creates the `hostPath` directory as `root` with 755
permissions, and the pod `fsGroup` **is not applied** to `hostPath` volumes. DAM runs as
`uid 1000` / `gid 1001`, so it could not write: it stays at `1/2` with
`EACCES: permission denied, access '/opt/app/upload'` in its log and Helm times out. That is why
the script sets the directory to `1000:1001` with `2775` permissions, using an ephemeral pod (no
`sudo`).

> When DX is deleted with `common/99-cleanup.sh`, this volume is left `Released` (it is not
> deleted by itself): run `lab0-poc-wsl/01-storage.sh` again before reinstalling, and it recreates
> it empty.

## Step 5 · Ingress

```bash
lab0-poc-wsl/02-ingress.sh
```

It installs **ingress-nginx** (the same Ingress Controller as the reference cluster, so the Lab 1
`ingress-dx.yaml` works unchanged) with `hostNetwork`: it listens directly on ports 80 and 443 of
WSL, and **WSL forwards Windows `localhost` to WSL**, so the Windows browser reaches DX at
`https://dx-demo.127.0.0.1.nip.io`.

Check (it must answer 404, the ingress-nginx default page):

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/
```

> Ports 80 and 443 are taken in the WSL VM, shared by all your distros.

## Step 6 · The reduced-resources layer (`DX_POC=1`)

The **requests** of the HCL charts are sized for production: the base DX alone requests
~10.4 GiB and the four labs ~17 GiB, more than the WSL VM has (~15 GiB). But the real usage in a
demo is much lower (the Web Engine requests 4 GiB and uses ~2.7 GiB).

The PoC layer lowers **only the requests** (what Kubernetes adds up to decide whether a pod fits on
the node) of the components that request the most; the **limits** do not change:

| Component | Default request | PoC request |
|---|---|---|
| Web Engine | 4 GiB | 3 GiB |
| Image Processor | 2 GiB | 512 MiB |
| DAM | 1.5 GiB | 1 GiB |
| Persistence Node | 1 GiB | 768 MiB |
| OpenSearch (Lab 4) | 2 GiB | 1.5 GiB |
| File Processor (Lab 4) | 2 GiB | 512 MiB |
| Search Middleware (Lab 4) | 768 MiB | 512 MiB |

Result: the base DX goes from requesting **10.4 to 7.2 GiB**, and the four labs from ~17 to ~11 GiB.

## Step 7 · The labs

From here on, follow Labs 1 to 4 **unchanged**, starting with
[Lab 1](../lab1-dx-base/GUIDE.md) (`common/00-check-prereqs.sh`...).

---

## Measured times, memory and disk

Real run on a laptop with Windows 11 Home, 32 GB of RAM and 16 cores (WSL with the default
~15 GiB), with the `DX_POC=1` layer:

| Lab | Time | Note |
|---|---|---|
| 0 · k3s + Helm (steps 1-2) | ~3 min | Download of k3s and Helm |
| 0 · StorageClasses and Ingress (steps 4-5) | ~2 min | |
| 1 · Base DX | **~4 min** | Includes the **first download** of the HCL images (in parallel, 30-50 s each) |
| 2A · LDAP | ~5 min | |
| 2B · PostgreSQL | ~10 min | The transfer, ~9 min |
| 3A · IQ | ~7 min | |
| 3B · Custom MCP | ~2 min | |
| 4 · OpenSearch | ~7 min | |

| Resource, with the four labs running | Measured |
|---|---|
| Memory requests (what Kubernetes schedules) | 11.4 GiB of 15.3 (74 %). Without the PoC layer they would be ~17 GiB: **it would not fit** |
| Real memory usage | **12.6 GiB (82 %)**: it works with the default ~16 GB of WSL, but very tight; 24 GB is recommended |
| Real CPU usage | ~5 cores (31 % of 16) |
| Disk | ~20 GB of images + ~3 GB of volumes |

## PoC troubleshooting

| Symptom | Cause | Solution |
|---|---|---|
| DAM PVC in `Pending`: *"NodePath only supports ReadWriteOnce"* | `dx-deploy-rwx` points to the k3s `local-path` | Use the static StorageClass of `storage-poc.yaml` (`lab0-poc-wsl/01-storage.sh`) |
| DAM at `1/2` and Helm times out: `EACCES ... /opt/app/upload` in the DAM log | The `hostPath` directory belongs to `root` | `lab0-poc-wsl/01-storage.sh` sets it to `1000:1001` (repeat it and DAM becomes ready without a restart) |
| Pods in `Pending` with `Insufficient memory` | Not enough memory requests available | `DX_POC=1` in `env.sh`, or more memory in `.wslconfig` |
| The Windows browser does not open `https://dx-demo.127.0.0.1.nip.io` | ingress-nginx is not listening or WSL does not forward `localhost` | `curl http://localhost/` inside WSL must return 404; if it does and Windows does not, check `localhostForwarding` in `.wslconfig` (enabled by default) |
| `nip.io` does not resolve | No access to public DNS | Add `127.0.0.1 dx-demo.local` to the Windows and WSL `hosts` file and use that name in `DX_HOST` |

## Uninstalling the PoC

Only the labs (DX and what is in `dx-shared`), keeping k3s:

```bash
common/99-cleanup.sh --yes && lab0-poc-wsl/01-storage.sh
```

Everything, including the distro (Windows PowerShell; it deletes the whole distro and its data):

```powershell
wsl --unregister dx-poc
```
