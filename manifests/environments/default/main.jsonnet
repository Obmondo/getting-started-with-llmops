local gemma4_12B = (import 'gemma4/12b.libsonnet').gemma4_12b;

(import 'cilium.libsonnet') +
(import 'cert-manager.libsonnet') +

(import 'localpv-provisioner.libsonnet') +
(import 'cloudnative-pg.libsonnet') +

// Observability.
(import 'kube-prometheus.libsonnet') +

// Primitives for hosting an LLM.
(import 'gpu-operator.libsonnet') +
(import 'nvsentinel.libsonnet') +
(import 'hami.libsonnet') +
(import 'kserve.libsonnet') +
(import 'lmcache.libsonnet') +

// The LLM (Gemma 4, 12B).
(import 'gemma4/12b.libsonnet') +

// Agentic memory.
(import 'hindsight.libsonnet')(
  model=gemma4_12B.llmInferenceService.spec.model.name,
  modelBaseURL='http://%s-kserve-workload-svc.%s.svc.cluster.local:8000/v1' % [
    gemma4_12B.llmInferenceService.metadata.name,
    gemma4_12B.llmInferenceService.metadata.namespace,
  ],
) +

// AIOPs.
(import 'keep.libsonnet') +
(import 'holmesgpt.libsonnet')(
  model=gemma4_12B.llmInferenceService.spec.model.name,
  modelBaseURL='http://%s-kserve-workload-svc.%s.svc.cluster.local:8000/v1' % [
    gemma4_12B.llmInferenceService.metadata.name,
    gemma4_12B.llmInferenceService.metadata.namespace,
  ],
  prometheusURL='http://kube-prometheus-stack-prometheus.kube-prometheus-stack.svc.cluster.local:9090',
) +

{}
