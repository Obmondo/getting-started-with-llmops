local Utils = import './utils.libsonnet';
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';

local app = 'lmcache';

local allocatedRuntimeMemory = 5,

      // Allocate as much CPU memory as available after accounting for the OS and vLLM. A larger L1
      // cache means fewer L2 round-trips.
      l1CacheSize = 6,

      // Requested memory is L1 cache size + ~5GB overhead for Python runtime and server operations.
      requestedMemorySize = allocatedRuntimeMemory + l1CacheSize,
      limitedMemorySize = allocatedRuntimeMemory + (2 * l1CacheSize);

/*
  LMCache is a KV cache management layer for LLM inference. It turns KV cache from a temporary
  state into reusable AI-native knowledge that can be stored persistently, reused across multiple
  serving engines, monitored with an observability stack, and transformed for better generation
  quality. As a result, LMCache reduces TTFT (time-to-first-token) and improves throughput,
  especially for long-context agentic, multi-turn conversation, and knowledge-augmented workloads
  (e.g., RAG). LMCache is vendor-neutral. It can be used as a KV cache layer for a range of
  mainstream open-source serving engines, inference frameworks, hardware vendors, storage systems,
  and infrastructure providers. The vendor neutrality allows users to freely switch between serving
  engines and storage vendors, while reusing the stored KV caches.

  In short, a KV cache stores intermediate key (K) and value (V) computations for reuse during
  inference (after training), which results in a substantial speed-up when generating text. The
  downside of a KV cache is that it adds more complexity to the code, increases memory
  requirements, and can't be used during training. However, the inference speed-ups are often well
  worth the trade-offs in code complexity and memory when using LLMs in production.

  Refer to https://magazine.sebastianraschka.com/p/coding-the-kv-cache-in-llms to get an intuition
  about KV cache.

  LMCache is a KV cache management layer for LLM inference. It turns KV cache from a temporary
  state into reusable AI-native knowledge that can be stored persistently, reused across multiple
  serving engines, monitored with an observability stack, and transformed for better generation
  quality. As a result, LMCache reduces TTFT (time-to-first-token) and improves throughput,
  especially for long-context agentic, multi-turn conversation, and knowledge-augmented workloads
  (e.g., RAG).

  LMCache multiprocess (MP) mode runs LMCache as a standalone service that vLLM instances connect
  to over ZMQ. One LMCache server per node can serve multiple vLLM pods, providing process
  isolation, shared caching, and independent resource scaling.
*/
{
  /*
    TODOs :

      (1) Use RustFS as an L2 storage backend.

        We'll also enable KV cache compression. LMCache supports a per-adapter serde that
        transforms KV cache data on its way to and from an L2 adapter. Typical uses: quantization
        (shrink storage footprint), compression, encryption.

      (3) Use P2P KVCache sharing :

        In a multi-node deployment, every node runs its own LMCache server process, and each one
        caches the KV of the requests it has served in its local memory. Without sharing, a prefix
        that was computed on one node has to be recomputed from scratch when the same prefix
        arrives on a different node.

        Peer-to-peer (P2P) KV cache sharing turns the per-node caches into one logical cache. When
        a node looks up a prefix that is not in its own memory, it can read that prefix’s KV
        directly from the memory of the peer node that holds it, over the datacenter network using
        RDMA. The result is a much higher effective cache hit rate across the fleet, without any
        central storage tier in the hot path.

        The transfer is a one-sided RDMA read from the requesting node into its own L1 buffer; the
        node that owns the data is not interrupted to serve it. On an RDMA-capable network
        (InfiniBand / RoCE) this is dramatically faster than recomputing the prefix or
        round-tripping through a shared object store.
  */
  lmCache: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    // Copied from https://github.com/LMCache/LMCache/blob/dev/examples/multi_process/lmcache-daemonset.yaml.
    daemonSet: {
      apiVersion: 'apps/v1',
      kind: 'DaemonSet',
      metadata: {
        name: app,
        namespace: app,
      },
      spec: {
        selector: {
          matchLabels: {
            app: app,
          },
        },
        template: {
          metadata: {
            labels: {
              app: app,
            },
            annotations: {
              // GPUs are NOT requested in the DaemonSet – this allows GPUs to remain exclusively
              // allocated to vLLM pods. On classic GPU Operator installs the NVIDIA container
              // runtime (RuntimeClass nvidia) provides GPU access for IPC-based memory transfers.
              // On CDI+NRI installs there is no nvidia RuntimeClass; omit it and request a
              // management CDI device instead.
              ['nvidia.cdi.k8s.io/container.%s' % app]: 'management.nvidia.com/gpu=all',
            },
          },
          spec: {
            // LMCache pods on nodes without GPUs will crash with CUDA initialization errors. This
            // is expected – LMCache only needs to run on GPU nodes where vLLM pods are scheduled.
            nodeSelector: {
              'nvidia.com/gpu.present': 'true',
            },

            // So vLLM pods discover the LMCache server via status.hostIP.
            hostNetwork: true,

            // Both vLLM and LMCache containers mount /dev/shm from the host to enable CUDA IPC
            // memory sharing in the default (legacy) mode.
            // TODO : Migrate to isolated IPC.
            volumes: [{
              name: 'dev-shm',
              hostPath: {
                path: '/dev/shm',
                type: 'Directory',
              },
            }],

            containers: [{
              name: app,
              image: 'lmcache/standalone:v0.5.8',
              command: [
                // When the MP server is started via lmcache server (the recommended entry point),
                // a FastAPI-based HTTP frontend is exposed alongside the selected ZMQ or gRPC
                // request endpoint used by vLLM. This HTTP API is intended for operators,
                // orchestrators (e.g. Kubernetes), and debugging tools — it is not on the
                // inference data path.
                '/opt/venv/bin/lmcache',
                'server',

                '--http-host',
                '0.0.0.0',

                '--l1-size-gb',
                '%d' % l1CacheSize,
              ],

              ports: [{
                name: 'http',
                containerPort: 8080,
              }],

              volumeMounts: [{
                name: 'dev-shm',
                mountPath: '/dev/shm',
              }],

              resources: {
                requests: {
                  memory: requestedMemorySize,
                  cpu: '4',
                },
                limits: {
                  memory: requestedMemorySize * 2,
                  cpu: '8',
                },
              },

              livenessProbe: {
                httpGet: {
                  path: '/healthcheck',
                  port: 8080,
                },
                initialDelaySeconds: 10,
                periodSeconds: 30,
              },
              readinessProbe: {
                httpGet: {
                  path: '/healthcheck',
                  port: 8080,
                },
                initialDelaySeconds: 5,
                periodSeconds: 10,
              },
            }],
          },
        },
      },
    },

    podMonitor: {
      apiVersion: 'monitoring.coreos.com/v1',
      kind: 'PodMonitor',
      metadata: {
        name: app,
        namespace: app,
      },
      spec: {
        selector: {
          matchLabels: {
            app: app,
          },
        },
        podMetricsEndpoints: [{
          port: 'http',
          path: '/metrics',
          interval: '30s',
        }],
      },
    },
  }),
}
