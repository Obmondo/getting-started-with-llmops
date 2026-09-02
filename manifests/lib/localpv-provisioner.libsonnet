local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'localpv-provisioner';

// OpenEBS Dynamic LocalPV Provisioner is an open‐source Kubernetes component that automates the
// dynamic provisioning of local persistent volumes. It converts local storage available on
// Kubernetes nodes, such as hostPath directories into persistent volumes accessible via PVCs. The
// provisioner automatically assigns node affinity metadata, ensuring that pods run on the node
// hosting the storage. The tool simplifies local storage management by automating volume creation,
// binding, and cleanup processes for hostpaths. It overcomes challenges of static provisioning by
// dynamically allocating storage on demand. Overall, the provisioner offers a robust, scalable
// solution for managing local persistent hostpath volumes in Kubernetes.
{
  localPVProvisioner: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Helm.template(app, Utils.chartsDir('localpv-provisioner', std.thisFile), {
      version: '4.5.1',

      namespace: app,
      createNamespace: false,

      values: {
        hostpathClass: { isDefaultClass: true },
      },
    }),
  }),
}
