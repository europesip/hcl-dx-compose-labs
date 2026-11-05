# Lab 1B · Sample Script Application, deployed with Helm *(optional)*

**English** · [Español](GUIDE.es.md)

On **DX Compose**, custom Java portlets need the separately licensed *Java Transition Module*: the
native way to build your own applications is the **Script Application**, HTML, JavaScript and CSS
stored in WCM. HCL deploys Script Applications with its command line tool, DXClient. This lab
deploys one **with a Helm chart**, like the rest of the platform: no DXClient or developer tools on
your workstation, just `helm`.

The app is **Hello DX**, a small React application by EUROPESIP. It shows two integrations with the
DX REST APIs, **as the signed-in user**: who is signed in, and which WCM libraries they can read.
Source, chart and how it works: [github.com/europesip/hcl-dx-scriptapp-helm](https://github.com/europesip/hcl-dx-scriptapp-helm).

It only needs **Lab 1**. ⏱ ~1 min.

```
helm upgrade --install hello-dx oci://ghcr.io/europesip/charts/hcl-dx-scriptapp
   └─ Job (after every install and upgrade)
        ├─ bundle image  ─► the built app (index.html, assets/)
        └─ HCL DXClient  ─► dxclient deploy-scriptapplication push ─► WCM (Script Application Library)
```

## Step 1 · Accept the DXClient license

DXClient asks you to accept its license (an HCL license for non-warranted programs). Read it:

```bash
kubectl -n "$SHARED_NS" run dxclient-license --rm -i --restart=Never \
  --image="$DXCLIENT_IMAGE" --command -- /dxclient/bin/dxclient accept-license
```

and, to accept it, set in `env.sh`:

```bash
export DXCLIENT_ACCEPT_LICENSE=yes
```

## Step 2 · Deploy the app

```bash
lab1b-scriptapp/01-scriptapp-install.sh
```

It creates two secrets in `dx-shared` and installs the chart:

- `scriptapp-dx`: the DX user that pushes the app. In the lab, `wpsadmin`; in a real project, a
  technical user with Editor access to the Script Application Library.
- `scriptapp-dx-ca`: the CA of the DX certificate. The lab certificate is self-signed, so it is its
  own CA (DXClient, a Node.js tool, rejects it otherwise).

The log of the Job ends with `OK: 'europesip-hello-dx' is in WCM (content ID ...)`.

## Step 3 · Add it to a page (once)

In DX, edit a page, add a component, *Script Applications* → **Hello DX**, and publish. Every later
`helm upgrade` updates the same WCM item, so every page that uses it shows the new version.

## Check

```bash
lab1b-scriptapp/99-verify.sh
```

## Good to know

- **A push publishes at once**, without workflow. To review changes first, push into a WCM project
  (`--set dx.projectContext=...`).
- **WCM stores each file in one element of at most 5,000,000 bytes**: the Job refuses files over
  4.5 MB before touching DX.
- **Uninstalling the chart does not delete the app from WCM** (pages may use it): the repository of
  the chart explains how to remove it.
