local kserve = import 'kserve.libsonnet';

local modelURI = 'hf://google/gemma-4-12B-it-qat-w4a16-ct';

/*
  Gemma is a family of open models built by Google DeepMind. Gemma 4 models are multimodal,
  handling text and image input (with audio supported on E2B, E4B, and 12B) and generating text
  output Gemma 4 features a context window of up to 256K tokens and maintains multilingual support
  in over 140 languages.

  Featuring both Dense and Mixture-of-Experts (MoE) architectures, Gemma 4 is well-suited for tasks
  like text generation, coding, and reasoning. The models are available in five distinct sizes:
  E2B, E4B, 12B, 26B A4B, and 31B.

  The models employ a hybrid attention mechanism that interleaves local sliding window attention
  with full global attention, ensuring the final layer is always global. This hybrid design
  delivers the processing speed and low memory footprint of a lightweight model without sacrificing
  the deep awareness required for complex, long-context tasks. To optimize memory for long
  contexts, global layers feature unified Keys and Values, and apply Proportional RoPE (p-RoPE).

  Gemma 4 models handle a broad range of tasks across text, vision, and audio. Key capabilities
  include:

    (1) Thinking – Built-in reasoning mode that lets the model think step-by-step before answering.

    (2) Long Context – Context windows of up to 128K tokens (E2B/E4B) and 256K tokens (12B,
                      26B A4B/31B).

    (3) Image Understanding – Object detection, Document/PDF parsing, screen and UI understanding,
                              chart comprehension, OCR (including multilingual), handwriting
                              recognition, and pointing. Images can be processed at variable aspect
                              ratios and resolutions.

    (4) Video Understanding – Analyze video by processing sequences of frames.

    (5) Interleaved Multimodal Input – Freely mix text and images in any order within a single
                                       prompt.

    (6) Function Calling – Native support for structured tool use, enabling agentic workflows.

    (7) Coding – Code generation, completion, and correction.

    (8) Multilingual – Out-of-the-box support for 35+ languages, pre-trained on 140+ languages.

    (9) Audio (E2B, E4B, and 12B only) – Automatic speech recognition (ASR) and
                                         speech-to-translated-text translation across multiple
                                         languages.

  As open models become central to enterprise infrastructure, provenance and security are paramount.
  Developed by Google DeepMind, Gemma 4 undergoes the same rigorous safety evaluations as our
  proprietary Gemini models. Gemma 4 models were developed in partnership with internal safety and
  responsible AI teams. A range of automated as well as human evaluations were conducted to help
  improve model safety. These evaluations align with Google’s AI principles, as well as safety
  policies, which aim to prevent our generative AI models from generating harmful content,
  including:

    (1) Content related to child sexual abuse material and exploitation
    (2) Dangerous content (e.g., promoting suicide, or instructing in activities that could cause
      real-world harm)
    (3) Sexually explicit content
    (4) Hate speech (e.g., dehumanizing members of protected groups)
    (5) Harassment (e.g., encouraging violence against people)


  You can read more here : https://huggingface.co/google/gemma-4-26B-A4B-it.
*/
local llmInferenceService = {
  apiVersion: 'serving.kserve.io/v1alpha2',
  kind: 'LLMInferenceService',
  metadata: {
    name: 'gemma4-12b',
    namespace: kserve.kserve.namespace.metadata.name,
  },
  spec: {
    model: {
      uri: modelURI,
      name: 'google/gemma-4-12B-it-qat-w4a16-ct',
    },

    replicas: 1,

    template: {
      containers: [{
        name: 'main',
        image: 'vllm/vllm-openai:gemma',

        // REFER : docs.vllm.ai/projects/recipes/en/stable/Google/Gemma4.html.
        args: [
          '--chat-template',
          '/vllm-workspace/examples/tool_chat_template_gemma4.jinja',

          // Context Window.
          '--max-model-len',
          '262144',

          // KV cache quantization.
          '--kv-cache-dtype',
          'fp8',

          /*
            NOT disabling multimodal here, deliberately.

            --limit-mm-per-prompt expects JSON and cannot be passed intact through this path. Two
            different failures, both from the same argument:

              {"image":0,"video":0,"audio":0}
                -> Value image:0 cannot be converted to <function loads>
                   (the value is split on commas, then each fragment is fed to json.loads)

              {"image":0}
                -> Value {image:0} cannot be converted to <function loads>
                   (no comma to split on, but the double quotes are stripped before the process
                    sees them, leaving something that is not JSON)

            So the argument survives neither form. What it would have bought is small - the vision
            tower's encoder cache, logged at startup as a 2496-token budget - and the model serves
            text correctly with it present, because clients here never send image content.
          */


          // Enable Gemma 4 thinking/reasoning parser.
          '--reasoning-parser',
          'gemma4',

          // Enable Gemma 4 tool call parser.
          '--tool-call-parser',
          'gemma4',
          // Auto-detect tool calls in output.
          '--enable-auto-tool-choice',

          // For arbitrary code execution.
          '--trust-remote-code',

          // Balancing between throughput and latency.
          // TODO : Understand the meaning of throughput and latency.
          '--max-num-seqs',
          '128',

          /*
            When set to True, perform async scheduling. This may help reduce the CPU overheads,
            leading to better latency and throughput. However, async scheduling is currently not
            supported with some features such as structured outputs, speculative decoding, and
            pipeline parallelism.

            It's experimental. And turned on by default, in the image that we're using, causing
            the following error :

              RuntimeError: State error: sample_tokens() must be called after execute_model()
                            returns None.
          */
          '--no-async-scheduling',
        ],

        // The kserve-config-llm-template preset sets `runAsNonRoot: true` on this container, but
        // the vLLM image declares no USER and runs as root - so the kubelet refuses to start it
        // with "container has runAsNonRoot and image will run as root", before anything else is
        // attempted.
        securityContext: {
          runAsNonRoot: false,
          runAsUser: 0,
        },

        resources: {
          requests: {
            'nvidia.com/gpu': '1',
            cpu: '4',
            memory: '16Gi',
          },
          limits: {
            'nvidia.com/gpu': '1',
            cpu: '6',
            memory: '32Gi',
          },
        },
      }],

    },

    /*
      Since we're deploying a single LLM in a single node, we don't need :

        (1) llm-d's KV cache aware routing feature for now. So, we're skipping installation of
          Envoy Gateway and Envoy AI Gateway.

        (2) tensor parallelism and decoupling decoding. So, we're skipping installation of
          LeaderWorkerSet (LDS).
    */
  },
};

local localModelCacheSize = 12;  // Gi.
local localModelCacheMaxNodeCount = 1;

local localModelNodeGroupStorageLimit = '%dGi' % [localModelCacheSize * localModelCacheMaxNodeCount];

local localModelNodeGroup = {
  apiVersion: 'serving.kserve.io/v1alpha1',
  kind: 'LocalModelNodeGroup',
  metadata: {
    name: 'gemma4-12b',
    namespace: '',
  },
  spec: {
    storageLimit: localModelNodeGroupStorageLimit,

    persistentVolumeSpec: {
      accessModes: ['ReadWriteOnce'],
      volumeMode: 'Filesystem',
      capacity: { storage: localModelNodeGroupStorageLimit },
      storageClassName: kserve.kserve.localModelStorageClass.metadata.name,
      'local': { path: '/models' },
      nodeAffinity: {
        required: {
          nodeSelectorTerms: [{
            matchExpressions: [{
              key: 'kserve/localmodel',
              operator: 'In',
              values: ['worker'],
            }],
          }],
        },
      },
    },

    persistentVolumeClaimSpec: {
      accessModes: ['ReadWriteOnce'],
      volumeMode: 'Filesystem',
      resources: { requests: { storage: localModelNodeGroupStorageLimit } },
      storageClassName: kserve.kserve.localModelStorageClass.metadata.name,
    },
  },
};

local localModelCache = {
  apiVersion: 'serving.kserve.io/v1alpha1',
  kind: 'LocalModelCache',
  metadata: {
    name: 'gemma4-12b',
    namespace: '',
  },
  spec: {
    sourceModelUri: modelURI,
    modelSize: '12Gi',
    nodeGroups: [localModelNodeGroup.metadata.name],
  },
};

{
  llmInferenceService: llmInferenceService,

  localModelNodeGroup: localModelNodeGroup,
  localModelCache: localModelCache,
}
