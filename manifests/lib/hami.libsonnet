local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'hami';

/*
  HAMi (Heterogeneous AI Computing Virtualization Middleware) is an open source platform for
  managing heterogeneous AI computing devices in Kubernetes clusters. Formerly known as
  k8s-vGPU-scheduler, HAMi enables device sharing across multiple containers and workloads.

  In AI inference scenarios, a common dilemma is that GPUs are expensive, but mostly idle.

  A typical inference service often only uses 20%~40% of the GPU's compute and a small amount of
  VRAM, leaving the rest idle. Kubernetes' default GPU scheduling model is exclusive:
  nvidia.com/gpu: 1 means the entire card is yours, and all other Pods must wait. Want to share a
  single GPU across multiple inference services? The standard Device Plugin cannot do it, because
  it can only report device counts (integers) to the scheduler - there is no concept of
  "VRAM quota."

  This led to various GPU sharing solutions. NVIDIA's official Time-Slicing allows multiple Pods to
  be scheduled concurrently, but provides no VRAM isolation - a Pod OOM can crash all tasks on the
  card. MIG hardware partitioning offers true isolation, but only datacenter-grade cards like A100
  and H100 support it.

  HAMi takes a different approach: no driver changes, no application changes - it achieves GPU
  virtualization at the software layer through CUDA API interception. Multiple Pods share the same
  physical GPU, and each Pod can only "see" the VRAM it requested. Over-allocation directly returns
  OOM.

  You can read more here : https://project-hami.io/docs/core-concepts/gpu-virtualization.

  Device Plugin :

    Kubernetes does not natively manage GPU or other heterogeneous hardware resources. To address
    this, Kubernetes provides the Device Plugin extension mechanism, which allows hardware vendors
    to register custom device resources with Kubelet for use by the scheduler.

    A Device Plugin itself is deployed as a DaemonSet, running on each GPU node. It is responsible
    for registering devices with Kubelet, reporting resources, and responding to allocation
    requests.

    Device Plugin has a fundamental limitation: the ListAndWatch interface can only report device
    counts (integers). The scheduler has no visibility into device-specific attributes: VRAM size,
    model, NUMA topology. This is why HAMi has to use Node Annotations to pass GPU specifications.

  DRA (Dynamic Resource Allocation) :

    DRA is Kubernetes' next-generation solution for this, promoted to GA in v1.34. It introduces a
    new set of APIs:

      (1) ResourceClaim: A Pod's declaration to claim device resources, analogous to how a PVC
                         claims a PV.

      (2) DeviceClass: Describes device specifications and filtering criteria for a class of
                       devices, supporting CEL expressions for fine-grained matching (e.g.,
                       "VRAM ≥ 16GB and model is A100").

      (3) ResourceSlice: The list of available devices reported by the device driver to the API
                         Server, carrying complete attributes.

    The scheduler can directly read device attributes from ResourceSlice for scheduling decisions.
    DRA also natively supports multiple Pods sharing the same device and cross-container device
    topology alignment.

  HAMi currently remains based on Device Plugin, but the official team has launched the HAMi-DRA
  subproject (v0.1.0, requires Kubernetes 1.34+), which converts HAMi's GPU resource requests into
  DRA ResourceClaim via MutatingWebhook, serving as a transitional solution for migrating to DRA.
*/
{
  hami: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Helm.template(app, Utils.chartsDir('hami-dra', std.thisFile), {
      version: '0.2.1',

      namespace: app,
      createNamespace: false,

      values: {
        // The monitor component collects GPU resource metrics via Prometheus. It serves them on
        // port 8080 (named `metrics` on the Service below), and its health probes on port 8000.
        monitor: {
          enabled: true,
          service: { type: 'ClusterIP' },
        },
      },
    }),

    serviceMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'ServiceMonitor',
      metadata: {
        name: app,
        namespace: app,
      },
      spec: {
        // The chart labels the monitor Service with `hami-dra-monitor.selectorLabels`, which
        // derives the name and instance from the Helm release name.
        selector: {
          matchLabels: {
            'app.kubernetes.io/name': app,
            'app.kubernetes.io/instance': app,
            'app.kubernetes.io/component': 'monitor',
          },
        },
        namespaceSelector: {
          matchNames: [app],
        },
        endpoints: [{
          port: 'metrics',
          path: '/metrics',
          interval: '30s',
        }],
      },
    },
  }),
}
