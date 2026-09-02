local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'gpu-operator';

/*
  Kubernetes provides access to special hardware resources such as NVIDIA GPUs, NICs, Infiniband
  adapters and other devices through the device plugin framework. However, configuring and
  managing nodes with these hardware resources requires configuration of multiple software
  components such as drivers, container runtimes or other libraries which are difficult and prone
  to errors. The NVIDIA GPU Operator uses the operator framework within Kubernetes to automate the
  management of all NVIDIA software components needed to provision GPU. These components include
  the NVIDIA drivers (to enable CUDA), Kubernetes device plugin for GPUs, the NVIDIA Container
  Toolkit, automatic node labeling using GFD, DCGM based monitoring and others.
*/
{
  gpuOperator: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Helm.template(app, Utils.chartsDir(app, std.thisFile), {
      version: 'v26.3.0',

      namespace: app,
      createNamespace: false,

      values: {
        // The Container Device Interface (CDI) is an open specification for container runtimes
        // that abstracts what access to a device, such as an NVIDIA GPU, means, and standardizes
        // access across container runtimes. Popular container runtimes can read and process the
        // specification to ensure that a device is available in a container.
        cdi: {
          enabled: true,

          // Node Resource Interface (NRI) is a standardized interface for plugging in extensions,
          // called NRI Plugins, to OCI-compatible container runtimes like containerd. NRI Plugins
          // serve as hooks which intercept pod and container lifecycle events and perform
          // functions including injecting devices to a container, topology aware placement
          // strategies, and more.
          nriPluginEnabled: true,
        },

        // NVIDIA Data Center GPU Manager (DCGM) is a suite of tools for managing and monitoring
        // NVIDIA Datacenter GPUs in cluster environments. It includes active health monitoring,
        // comprehensive diagnostics, system alerts, and governance policies including power and
        // clock management.
        // DCGM integrates into the Kubernetes ecosystem using DCGM-Exporter to provide rich GPU
        // telemetry in containerized environments.
        dcgmExporter: { enabled: true },

        // The VM already has NVIDIA driver installed, because of the Ubuntu 22.4 template that
        // we're using.
        driver: { enabled: false },

        // NOTE : We're using HAMi for GPU sharing.
        /*
          MIG enables multiple GPU Instances to run in parallel on a single, physical NVIDIA
          Ampere architecture GPU.

          The new Multi-Instance GPU (MIG) feature allows GPUs (starting with NVIDIA Ampere
          architecture) to be securely partitioned into up to seven separate GPU Instances for
          CUDA applications, providing multiple users with separate GPU resources for optimal GPU
          utilization.

          With MIG, each instance’s processors have separate and isolated paths through the entire
          memory system - the on-chip crossbar ports, L2 cache banks, memory controllers, and DRAM
          address busses are all assigned uniquely to an individual instance. This ensures that an
          individual user’s workload can run with predictable throughput and latency, with the
          same L2 cache allocation and DRAM bandwidth, even if other tasks are thrashing their own
          caches or saturating their DRAM interfaces.

          NOTE : Aside MIG, another strategy for sharing a physical GPU is time slicing.
        */
        /*
          mig: {
            // MIG mode is enabled on all GPUs on a node.
            strategy: 'single',

            // When MIG is enabled, nodes are labeled with nvidia.com/mig.config: all-disabled by
            // default. To use a profile on a node, update the label value with the desired profile,
            // for example, nvidia.com/mig.config=all-1g.10gb.
          },

          // Introduced in GPU Operator v26.3.0, MIG Manager generates the MIG configuration for a
          // node at runtime from the available hardware. The configuration is generated on startup,
          // discovering MIG profiles for each MIG-capable GPU on a node using NVIDIA Management
          // Library (NVML), then writing it to a ConfigMap for each MIG-capable node in your cluster.
          migManager: { enabled: true },
        */
      },
    }),
  }),
}
