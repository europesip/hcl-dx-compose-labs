# Kubernetes frente a OpenShift

[English](kubernetes-vs-openshift.md) · **Español**

Los charts de HCL son los mismos en las dos plataformas y los `custom-values` de los labs también.
Las diferencias están en **cómo se prepara el namespace, cómo se publica DX y quién instala**.

> **En el clúster de referencia de los labs usamos k3s** (Kubernetes estándar). Cambiar `PLATFORM=openshift` en `env.sh`
> activa las variantes de OpenShift en los scripts que las tienen (namespaces y acceso externo).

## Resumen

| Tema | Kubernetes (k3s en los labs) | OpenShift |
|---|---|---|
| Cliente | `kubectl` | `oc` (o `kubectl`, que también funciona) |
| **Namespace de DX** | `kubectl create namespace dx-demo`, sin más | Namespace con **anotaciones SCC** exigidas por HCL (ver abajo) |
| Seguridad de pods | Pod Security Standards; DX funciona con el nivel por defecto de k3s | SCC `restricted-v2`: los UID deben estar en el rango del namespace |
| Usuario instalador | Normalmente el kubeconfig de administrador | Habitual separar `kubeadmin` (prepara) y `dxadmin` (instala, rol `admin` en el namespace + `dx-installer-extra-perms`) |
| Publicar DX | **Ingress** (`lab1-dx-base/ingress-dx.yaml`): TLS en el Ingress y re-cifrado hacia HAProxy | **Route passthrough** (`lab1-dx-base/route-dx-openshift.yaml`): el TLS lo termina HAProxy |
| StorageClasses | Longhorn, NFS, local-path (no vale para RWX), discos cloud... | ODF (`ceph-rbd` RWO, `cephfs` RWX), NFS... |
| Operador PostgreSQL | Chart Helm `cnpg/cloudnative-pg` en `dx-shared` | **OperatorHub** → CloudNativePG (certificado) |
| OpenLDAP de laboratorio | Chart `openldap-stack-ha` tal cual | Desactivar `podSecurityContext`/`containerSecurityContext` del chart (comentado en `openldap-values.yaml`) |
| Tráfico entre namespaces | Abierto por defecto (sin NetworkPolicies) | Abierto por defecto, pero muchos clústeres aplican aislamiento por proyecto: hace falta una NetworkPolicy que permita `dx-demo → dx-shared` |

## El namespace en OpenShift

HCL indica crear el namespace de DX con estas anotaciones
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

**Por qué.** OpenShift asigna a cada proyecto un rango de UID aleatorio y alto (p. ej.
`1000680000/10000`), y la SCC `restricted-v2` obliga a los pods a ejecutarse dentro de él. Los
contenedores de DX esperan el UID/GID 1000-1001 (permisos de ficheros en las imágenes y en los
volúmenes). Con estas anotaciones el rango del proyecto empieza en 1000, así que los pods de DX
arrancan sin SCC privilegiadas. **En Kubernetes no hay asignación de rangos**: el pod usa el UID que
declara su `securityContext`, por eso basta con `kubectl create namespace`.

Las anotaciones hay que ponerlas **al crear** el namespace (`oc new-project` no las admite): si el
proyecto ya existe con otro rango, los PVC ya creados tendrán otro propietario. En los labs lo hace
`common/01-namespaces.sh` con `common/openshift/namespaces.yaml`.

`dx-shared` no necesita anotaciones: CNPG y LiteLLM funcionan con el rango que asigne OpenShift.

## Usuario restringido en OpenShift

Si DX lo instala un usuario sin `cluster-admin`, el administrador prepara antes:

```bash
oc apply -f common/openshift/namespaces.yaml        # tras sustituir las variables, o common/01-namespaces.sh
oc adm policy add-role-to-user admin dxadmin -n dx-demo
oc adm policy add-role-to-user admin dxadmin -n dx-shared
oc apply -f common/openshift/rbac-dx-installer.yaml
oc adm policy add-role-to-user dx-installer-extra-perms dxadmin -n dx-demo
```

El rol `admin` no cubre `EndpointSlices` ni `endpoints/restricted`, que crea el chart de DX: de ahí
el ClusterRole adicional (asignado solo en el namespace). Instalar el operador CNPG sí requiere
`cluster-admin` (crea CRD y webhooks globales).

## Acceso externo

- **Kubernetes**: el Ingress termina TLS con `dx-tls-cert` y vuelve a cifrar hacia el servicio
  `dx-deployment-haproxy:443` (`backend-protocol: HTTPS`). Con el **Traefik** que k3s
  instala por defecto (`INGRESS_CLASS=traefik`), una IngressRoute de Traefik hace lo mismo
  (`lab1-dx-base/ingressroute-dx-traefik.yaml`).
- **OpenShift**: Route con `termination: passthrough` hacia el puerto `haproxy` del mismo servicio.
  El router no descifra; el certificado que ve el navegador es el de HAProxy (`dx-tls-cert`).

En los dos casos `networking.haproxy.serviceType: ClusterIP` y el FQDN es `networking.webEngine.host`.
