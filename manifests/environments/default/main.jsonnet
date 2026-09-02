local gemma4_12B = import 'gemma4/12B.libsonnet';

(import 'cilium.libsonnet') +
(import 'cert-manager.libsonnet') +

(import 'localpv-provisioner.libsonnet') +

(import 'cloudnative-pg.libsonnet') +

(import 'kube-prometheus.libsonnet') +

(import 'gpu-operator.libsonnet') +
(import 'nvsentinel.libsonnet') +
// There is an issue in the Helm chart, due to which renderring fails.
// (import 'hami.libsonnet') +
(import 'lmcache.libsonnet') +
(import 'kserve.libsonnet') +

(import 'hindsight.libsonnet')(
  model=gemma4_12B.llmInferenceService.spec.model.name,
  modelBaseURL='http://%s-kserve-workload-svc.%s.svc.cluster.local:8000/v1' % [
    gemma4_12B.llmInferenceService.metadata.name,
    gemma4_12B.llmInferenceService.metadata.namespace,
  ],
) +

{}
