local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local CloudNativePG = import './cloudnative-pg.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'nvsentinel';

local healthEventsStoreName = 'health-events';

local healthEventsStore = CloudNativePG.newCluster(healthEventsStoreName, app) + {
  cluster+: {
    spec+: {
      bootstrap: {
        initdb: {
          database: healthEventsStoreName,
          owner: app,
        },
      },
    },
  },
};

// NVSentinel automatically detects, classifies, and remediates hardware and software faults in
// GPU nodes. It monitors GPU health, system logs, and cloud provider maintenance events, then
// takes action: cordoning faulty nodes, draining workloads, and triggering break-fix workflows.
{
  nvsentinel: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Utils.withNamespace(app, Helm.template(app, Utils.chartsDir(app, std.thisFile), {
      version: 'v1.18.0',

      namespace: app,
      createNamespace: false,

      values: {
        global: {
          // The GPU health monitor module is enabled by default.

          // Health Events Analyzer - analyzes patterns in health events. Provides insights and
          // recommendations based on historical data.
          healthEventsAnalyzer: { enabled: true },

          // Fault Quarantine Module - cordons/taints nodes with detected faults Prevents new
          // workloads from scheduling on failing nodes.
          faultQuarantine: { enabled: true },

          // When a node gets marked as faulty, NVSentinel can also gracefully terminate pods on
          // that node, thus draining it. And then reboots / terminates the node by communicating
          // with the underlying cloud-provider.

          datastore: {
            provider: 'postgresql',

            connection: {
              host: '%s-rw.%s.svc.cluster.local' % [healthEventsStoreName, app],
              port: 5432,
              database: healthEventsStoreName,
              username: app,
              sslmode: 'disable',
            },

            auth: {
              mechanism: 'scram',
              existingSecret: healthEventsStoreName + '-app',
            },
          },
        },

        networkPolicy: { enabled: false },

        // The client certificate is mounted whenever this path is set, independently of the
        // connection's sslmode - so with sslmode disable the pods still fail to start on
        // `secret "postgresql-client-cert" not found`. Emptying it drops the mount.
        platformConnector: {
          postgresqlStore: { clientCertMountPath: '' },
        },
        'health-events-analyzer': { clientCertMountPath: '' },
        'fault-quarantine': { clientCertMountPath: '' },
        'fault-remediation': { clientCertMountPath: '' },
        'csp-health-monitor': { clientCertMountPath: '' },
        'node-drainer': { clientCertMountPath: '' },
      },
    })),

    healthEventsStore: healthEventsStore,
  }),
}
