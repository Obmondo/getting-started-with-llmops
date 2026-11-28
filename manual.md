# Manual steps

Everything the jsonnet manifests cannot reproduce. A node rebuilt or a cluster recreated from
`make render` plus `kubectl apply` arrives without the items below.

### Ownership of the KServe local model cache

The `LocalModelNodeGroup` points a `local` PersistentVolume at `/models` on the host. Two
components with different identities write there: the `kserve-localmodelnode-agent` runs as uid
`65532` (the distroless nonroot user, with `runAsNonRoot` and a read-only root filesystem), and the
download Job runs with `fsGroup: 1000`. A fresh `root:root 0755` directory fails both, first with
`mkdir /mnt/models/models: permission denied` and then with
`Permission denied: '/mnt/models/.cache'`.

```bash
mkdir -p /models
chown -R 65532:1000 /models
find /models -type d -exec chmod 2775 {} \;
```

The setgid bit matters: new directories inherit group `1000`, so the download Job keeps write
access to paths the agent creates later.

## Workstation

### Reaching the Keep UI

The chart's own Ingress routes `/`, `/v2` and `/websocket` on one host to the frontend, the backend
and soketi, and that Ingress needs an nginx controller. There is none in this cluster, so the UI is
reached by port-forwarding the two Services it talks to. `frontend.env` sets `PUSHER_HOST` to
`localhost` and `PUSHER_PORT` to `6001` for exactly this, so the port numbers below are not
arbitrary.

```bash
kubectl -n keep port-forward svc/keep-frontend 3000:3000
```

```bash
kubectl -n keep port-forward svc/keep-websocket 6001:6001
```

Then open http://localhost:3000. Without the second forward the UI loads but its live updates fail
with `Firefox can't establish a connection to the server at ws://localhost:6001/app/keepappkey`.

### The GitHub token's permissions

The token itself lives in `manifests/lib/github.libsonnet`, which both the HolmesGPT Secret and
Keep's workflow are rendered from, but its scopes are set in GitHub rather than here. Filing an
issue needs `Issues: write`. Opening a pull request needs `Contents: read and write`, because the
branch and its commit are contents writes, and `Pull requests: write` for the pull request itself.

## Cluster state created by hand

Nothing at present. Alert output goes to GitHub issues and pull requests, which HolmesGPT creates
through its own GitHub toolset, so there is no hand-made channel or identity to recreate.
