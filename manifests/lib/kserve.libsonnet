local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'kserve',
      version = 'v0.20.0';

local localModelStorageClass = {
  apiVersion: 'storage.k8s.io/v1',
  kind: 'StorageClass',
  metadata: { name: 'local-storage' },
  provisioner: 'kubernetes.io/no-provisioner',
  volumeBindingMode: 'WaitForFirstConsumer',
};

/*
  KServe eliminates the complexity of productionizing AI models. Whether you're a data scientist,
  DevOps engineer, or platform architect, KServe provides a unified solution that works across
  clouds and scales with your needs.

  KServe offers two powerful deployment modes to fit diverse operational needs:

    (1) Standard Mode (Highly Recommended for LLM Serving): Deploys KServe components as standard
      Kubernetes Deployments, providing maximum control, reliability, and compatibility with
      enterprise Kubernetes environments. Standard mode is ideal for users who require predictable
      scaling, advanced networking, and direct integration with Kubernetes-native tools. This mode
      is now the preferred choice for most production scenarios, and is especially recommended for
      serving Large Language Models (LLMs) due to its flexibility and advanced features.

    (2) Knative Mode: Leverages Knative for automatic scaling, including scale-to-zero. This mode
      is well-suited for dynamic workloads and environments where resource efficiency is critical,
      but may introduce additional complexity and dependencies.

  Its architecture separates management (control plane) from high-performance inference (data
  plane), supporting a wide range of ML frameworks and deployment patterns.

    (1) Control Plane: Manages the lifecycle of inference services, inference graphs, resource
                       orchestration, autoscaling, and integration with Kubernetes APIs.

    (2) Data Plane: Executes inference requests, model transformations, and explanations with high
                    throughput and low latency.

  KServe has two control plane implementations depending on which resource you deploy:

    (1) InferenceService : Best for predictive models & standard GenAI.

    (2) LLMInferenceService : Best for advanced LLM workloads.

      The LLMInferenceService CRD is purpose-built for large language model workloads. Unlike the
      standard InferenceService, it exposes primitives for KV-cache offloading, prefix-aware
      routing, disaggregated prefill/decode serving, and fine-grained GPU scheduling — capabilities
      that become critical at scale.

      It uses llm-d under the hood.

  KServe's data plane introduces an inference API that is independent of any specific ML/DL
  framework and model server. This allows for quick iterations and consistency across Inference
  Services and supports both easy-to-use and high-performance use cases.

  For traditional ML models, KServe offers the V1 and Open Inference Protocol (V2) inference
  protocols, while for generative AI workloads, it supports the OpenAI-compatible API specification
  which has become the de facto standard for large language model (LLM) interactions. This enables
  seamless integration with popular LLM clients and tools while providing streaming capabilities
  essential for generative AI applications.

  By implementing these protocols, both inference clients and servers increase their utility and
  portability by operating seamlessly on platforms that have standardized around these APIs.
  KServe's inference protocol is endorsed by NVIDIA Triton Inference Server, TensorFlow Serving and
  TorchServe.

  The Generative Inference architecture in KServe is specifically designed to handle large language
  models (LLMs) and other generative AI workloads that require specialized handling for streaming
  responses, token-by-token generation, and efficient memory management.

  You can see the architecture here : https://kserve.github.io/website/docs/concepts/architecture/data-plane#generative-inference-architecture.

  The Hugging Face serving runtime in KServe is a specialized model server designed to deploy and
  serve Hugging Face models with high performance and scalability. It uses vLLM backend engine
  which is optimized for Large Language Models (LLMs) with high-performance text generation
  capabilities.

  vLLM implements several state-of-the-art inference optimization techniques, including:

    (1) PagedAttention for efficient key and value memory management
    (2) Speculative decoding for improved latency
    (3) Continuous batching for higher throughput
    (4) Chunked prefill
    (5) Prefix caching
    (6) Optimized CUDA kernels for faster computation

  While, the runtime also supports the standard Hugging Face backend for models for predictive
  tasks such as text classification, token classification, and fill-mask. When a model is not
  supported by the vLLM engine, KServe automatically falls back to the standard Hugging Face
  backend to ensure compatibility across a wide range of models.

  The Hugging Face runtime provides pre-built container images optimized for different hardware
  environments:

    (1) CUDA-enabled Image: Optimized for GPU acceleration with CUDA libraries

    (2) CPU Image: Optimized for CPU-only environments with AVX512 instructions disabled for
                   compatibility

  KServe automatically selects the appropriate image based on the resources specified in your
  InferenceService.

  The Hugging Face runtime supports several advanced features to enhance model serving capabilities:

    (1) Model Caching: Cache models on local storage for faster loading and reduced latency. This
      is particularly useful for large models that are frequently accessed.

    (2) KV Cache Offloading: Offload key-value caches to CPU memory to reduce GPU memory usage,
      allowing larger models to be served on GPUs with limited memory.

    (3) Distributed LLM Serving: Scale model serving across multiple nodes and GPUs for high
      throughput and low latency. This is useful for serving large models or handling high request
      volumes.

    (4) AI Gateway: Use the AI Gateway to manage rate-limiting based on tokens and route requests
      to different models, providing a unified API for various generative tasks.
*/
{
  kserve: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: {
      crd: Helm.template('kserve-crd', Utils.chartsDir('kserve-crd', std.thisFile), {
        version: 'v0.20.0',

        namespace: app,
        createNamespace: false,

        values: {},
      }),

      llmInferenceService: {
        crd: (
          local rendered = Helm.template('kserve-llmisvc-crd', Utils.chartsDir('kserve-llmisvc-crd', std.thisFile), {
            version: version,

            namespace: app,
            createNamespace: false,

            values: {},
          });

          local duplicateCRDs = ['clusterstoragecontainers.serving.kserve.io'];

          {
            [key]: rendered[key]
            for key in std.objectFields(rendered)
            if !std.member(duplicateCRDs, rendered[key].metadata.name)
          }
        ),

        resources: Helm.template('kserve-llmisvc-resources', Utils.chartsDir('kserve-llmisvc-resources', std.thisFile), {
          version: version,

          namespace: app,
          createNamespace: false,

          values: {
            kserve: {
              controller: { deploymentMode: 'Standard' },

              // When using the default memory quota, the storage initializer container gets
              // OOMKilled, when downloading Gemma4 model weights.
              storage: {
                resources: {
                  requests: {
                    memory: '2Gi',
                  },
                  limits: {
                    memory: '32Gi',
                  },
                },
              },

              localmodel: { enabled: true },
            },
          },
        }),
      },

      /*
        By caching LLM models locally, the InferenceService startup time can be greatly improved.
        For deployments with more than one replica, the local persistent volume can serve multiple
        pods with the warmed up model cache.

        This feature introduces the following custom resources:

          (1) LocalModelCache - Cluster-scoped resource that specifies which model from persistent
            storage to cache on local storage of the Kubernetes node. Cached models are available
            to InferenceService resources in any namespace.

          (2) LocalModelNamespaceCache - Namespace-scoped variant of LocalModelCache. Cached models
            are only available to InferenceService resources within the same namespace, enabling
            multi-tenancy and isolation.

          (3) LocalModelNodeGroup - Manages the node group for caching the models and the local
            persistent storage.

          (4) LocalModelNode - Tracks the status of the models cached on a given local node
      */
      localModel: {
        crd: Helm.template('kserve-localmodel-crd', Utils.chartsDir('kserve-localmodel-crd', std.thisFile), {
          version: version,

          namespace: app,
          createNamespace: false,

          values: {},
        }),

        resources: Helm.template('kserve-localmodel-resources', Utils.chartsDir('kserve-localmodel-resources', std.thisFile), {
          version: version,

          namespace: app,
          createNamespace: false,

          values: {
            kserve: {
              localmodel: { enabled: true },
            },
          },
        }),

        jobNamespace: Kubernetes.core.v1.namespace.new('kserve-localmodel-jobs'),
      },

      /*
        A full LLM inference deployment touches container images, probes, security contexts,
        scheduler settings, routing rules, resource limits, and more. Most users should not have to
        care about all of that. KServe ships sensible defaults that cover common deployments out of
        the box - a working service needs a model URI, a reference to a accelerator config, and a
        few feature toggles like routing and scheduling. When you do need to change something - a
        different GPU type, a custom routing policy, a longer startup probe - you override only
        that field and the defaults you did not touch stay in place.

        When you create an LLMInferenceService, the controller does not apply your spec directly.
        Instead, it builds an effective configuration by merging multiple sources together using
        Kubernetes strategic merge patch. This process - config composition - determines the final
        shape of the resources that will be responsible for reliably serving your model.

        Three types of configuration participate in the merge, each with a different owner and
        priority:

          (1) Well-known configs (shipped with KServe)
          (2) User baseRefs
          (3) LLMInferenceService spec

        All selected configs are merged in a fixed order.
      */
      wellKnownConfigs: Helm.template('kserve-runtime-configs', Utils.chartsDir('kserve-runtime-configs', std.thisFile), {
        version: version,

        namespace: app,
        createNamespace: false,

        values: {
          kserve: {
            llmisvcConfigs: { enabled: true },
          },
        },
      }),
    },

    localModelStorageClass: localModelStorageClass,

    gemma4: {
      '12b': import 'gemma4/12b.libsonnet',
    },
  }),
}
