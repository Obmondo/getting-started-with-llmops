local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'cloudnative-pg';

local newCluster = function(clusterName, namespace, connectionPoolingEnabled=false) {
  cluster: {
    apiVersion: 'postgresql.cnpg.io/v1',
    kind: 'Cluster',
    metadata: {
      name: clusterName,
      namespace: namespace,
    },
    spec: {
      instances: 1,

      storage: { size: '5Gi' },
    },
  },
};

// CloudNativePG (CNPG) is an open-source operator designed to manage PostgreSQL workloads on any
// supported Kubernetes cluster.
{
  cloudnativePG: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Helm.template(app, Utils.chartsDir(app, std.thisFile), {
      version: '0.28.2',

      namespace: app,
      createNamespace: false,

      values: {},
    }),
  }),

  newCluster:: newCluster,
}
