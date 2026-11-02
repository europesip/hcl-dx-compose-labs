# Collecting data for HCL Support

**English** · [Español](support.es.md)

If something fails and you need to open a case with HCL Support, collect the data they will ask for
**before** changing or deleting anything:

```bash
common/collect-support-data.sh --case CS1234567
```

It is the twin of [`common/99-cleanup.sh`](cleanup.md): one collects, the other deletes. It is
**read-only** (it changes nothing in the cluster) and leaves a `container_mustgather_<case>_<date>.tar.gz`
ready to upload to the case, following the HCL *HTTPS and SFTP upload and download instructions*.

| Option | What it does |
|---|---|
| `--case CS1234567` | Adds the case number to the file name and to the README |
| `--since 2h` | Only the logs of the last 2 hours (by default, all) |
| `--liberty-dump` | Also a Liberty `server dump` of the Web Engine (logs, configuration, thread dumps) |
| `--out <dir>` | Where to leave the result (by default, the current folder) |

## What it collects

It follows the HCL technote **"Collecting Data: HCL DX Containers on Kubernetes/OpenShift"
(KB0094817)**, with the same file names so that HCL Support recognises them, and with `oc` instead of
`kubectl` on OpenShift:

| File | Content |
|---|---|
| `kube-version.txt`, `nodes.txt` | Kubernetes and Helm versions, nodes |
| `pods.txt`, `describePods.txt`, `dx-resources.txt` | Pods, their `describe` and every object of the namespace |
| `configmap.yaml`, `deployment.yaml` | ConfigMaps, Deployments and StatefulSets |
| `CRD.txt` | `describe` of the CRDs related to the labs (the full list in `CRD-list.txt`) |
| `DX-PV.txt`, `DX-PVC.txt`, `core-pv.yaml`, `dam_pv.yaml` | Volumes; the Web Engine and DAM ones are detected by themselves |
| `event.txt` | Events of the namespace |
| `currentLogs-<release>.txt` | Logs of every Helm release (`-l release=<release>`) |
| `non-running_pod*.txt` | Logs and `describe` of any pod that is not running or not ready |

And what the technote does not cover for DX Compose:

- **The Open Liberty logs of the Web Engine** (`web-engine/liberty-logs/`). The technote points to
  `wpcollector`, but that tool belongs to DX Core on WebSphere: DX Compose runs the Web Engine on Open
  Liberty and does not have it.
- **The logs of every container**, current and previous start (`logs/`).
- **The Helm releases**: `helm ls`, the user-supplied values and the history (`helm/`).
- **The third-party namespace** of the labs (PostgreSQL, OpenLDAP, LiteLLM, custom MCP), in a subfolder.

## What it does not collect

- **Secrets**: only their names (`secret-names.txt`).
- **Sensitive ConfigMaps**: the demo LDIF (password hashes) and the PostgreSQL preparation script.
- Before packing, it **masks** the passwords, keys and tokens of `env.sh`, the LiteLLM master key, and
  any `sk-…` key, `LtpaToken2` or `Bearer` value. The result is kept in a folder next to the
  `.tar.gz`: review it before sending.

## Debug logging

For some problems HCL Support needs debug logs, as the technote explains: set the `logging:` levels of
the component in your values (for example `api:server-v1:*=debug` for DAM or IQ), run the
`helm upgrade`, reproduce the problem and then collect.
