local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'cert-manager';

// CertManager adds certificates and certificate issuers as resource types in Kubernetes clusters,
// and simplifies the process of obtaining, renewing and using those certificates. It can issue
// certificates from a variety of supported sources, including Let's Encrypt, HashiCorp Vault etc.
// It will ensure certificates are valid and up to date, and attempt to renew certificates at a
// configured time before expiry.
{
  certManager: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Helm.template(app, Utils.chartsDir(app, std.thisFile), {
      version: '1.20.2',

      namespace: app,
      createNamespace: false,

      values: {
        crds: { enabled: true },
      },
    }),
  }),
}
