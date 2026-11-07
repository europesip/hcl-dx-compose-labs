# Kubernetes versus OpenShift

**English** · [Español](kubernetes-vs-openshift.es.md)

The HCL charts are the same on both platforms and so are the lab `custom-values`. The differences
are in **how the namespace is prepared, how DX is published and who installs**.

> **The reference lab cluster uses k3s** (standard Kubernetes). Setting `PLATFORM=openshift` in
> `env.sh` enables the OpenShift variants in the scripts that have them (namespaces and external
> access).

## Summary

| Topic | Kubernetes (k3s in the labs) | OpenShift |
|---|---|---|
| Client | `kubectl` | `oc` (or `kubectl`, which also works) |
| **DX namespace** | `kubectl create namespace dx-demo`, nothing else | Namespace with the **SCC annotations** required by HCL (see below) |
| Pod security | Pod Security Standards; DX works with the k3s default level | `restricted-v2` SCC: UIDs must be in the namespace range |
| Installing user | Usually the administrator kubeconfig | Common to separate `kubeadmin` (prepares) and `dxadmin` (installs, `admin` role in the namespace + `dx-installer-extra-perms`) |
| Publishing DX | **Ingress** (`lab1-dx-base/ingress-dx.yaml`): TLS at the Ingress and re-encryption to HAProxy | **Passthrough Route** (`lab1-dx-base/route-dx-openshift.yaml`): TLS is terminated by HAProxy |
| StorageClasses | Longhorn, NFS, local-path (not valid for RWX), cloud disks... | ODF (`ceph-rbd` RWO, `cephfs` RWX), NFS... |
| PostgreSQL operator | Helm chart `cnpg/cloudnative-pg` in `dx-shared` | **OperatorHub** → CloudNativePG (certified) |
| Lab OpenLDAP | `openldap-stack-ha` chart as is | Disable the chart `podSecurityContext`/`containerSecurityContext` (commented in `openldap-values.yaml`) |
| Traffic between namespaces | Open by default (no NetworkPolicies) | Open by default, but many clusters apply per-project isolation: a NetworkPolicy allowing `dx-demo → dx-shared` is needed |

## The namespace on OpenShift

HCL says to create the DX namespace with these annotations
([Preparing the namespace, CF239](https://help.hcl-software.com/digital-experience/dx-compose/CF239/deploy_dx/install/kubernetes_deployment/preparation/mandatory_tasks/prepare_namespace/)):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dx-demo
  annotations:
    openshift.io/sa.scc.mcs: "s0:c24,c4"
    openshift.io/sa.scc.supplemental-groups: "1001/10000"
    openshift.io/sa.scc.uid-range: "1000/10000"
```

**Why.** OpenShift assigns every project a random, high UID range (e.g. `1000680000/10000`), and
the `restricted-v2` SCC forces the pods to run inside it. The DX containers expect UID/GID
1000-1001 (file permissions in the images and in the volumes). With these annotations the project
range starts at 1000, so the DX pods start without privileged SCCs. **Kubernetes has no range
assignment**: the pod uses the UID its `securityContext` declares, which is why `kubectl create
namespace` is enough.

The annotations have to be set **when the namespace is created** (`oc new-project` does not accept
them): if the project already exists with another range, the PVCs already created will have
another owner. In the labs `common/01-namespaces.sh` does it with `common/openshift/namespaces.yaml`.

`dx-shared` needs no annotations: CNPG and LiteLLM work with the range OpenShift assigns.

## Restricted user on OpenShift

If DX is installed by a user without `cluster-admin`, the administrator prepares beforehand:

```bash
oc apply -f common/openshift/namespaces.yaml        # after replacing the variables, or common/01-namespaces.sh
oc adm policy add-role-to-user admin dxadmin -n dx-demo
oc adm policy add-role-to-user admin dxadmin -n dx-shared
oc apply -f common/openshift/rbac-dx-installer.yaml
oc adm policy add-role-to-user dx-installer-extra-perms dxadmin -n dx-demo
```

The `admin` role does not cover `EndpointSlices` or `endpoints/restricted`, which the DX chart
creates: hence the extra ClusterRole (bound only in the namespace). Installing the CNPG operator
does require `cluster-admin` (it creates global CRDs and webhooks).

## External access

- **Kubernetes**: the Ingress terminates TLS with `dx-tls-cert` and re-encrypts towards the
  `dx-deployment-haproxy:443` service (`backend-protocol: HTTPS`). With the **Traefik** that k3s
  installs by default (`INGRESS_CLASS=traefik`), a Traefik IngressRoute does the same
  (`lab1-dx-base/ingressroute-dx-traefik.yaml`).
- **OpenShift**: Route with `termination: passthrough` to the `haproxy` port of the same service.
  The router does not decrypt; the certificate the browser sees is the HAProxy one (`dx-tls-cert`).

In both cases `networking.haproxy.serviceType: ClusterIP` and the FQDN is `networking.webEngine.host`.
