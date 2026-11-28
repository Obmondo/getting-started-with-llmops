local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local Utils = import './utils.libsonnet';

local app = 'holmesgpt';

/*
  HolmesGPT is an open-source SRE agent for investigating production incidents across any
  infrastructure — Kubernetes, VMs, cloud services, databases, and more.

    (1) Production systems generate enormous amounts of telemetry data. HolmesGPT is designed to
      work at this scale without pulling unbounded data into context:

      (a) Where possible, filters and aggregations are pushed to the data source rather than
        fetching everything and parsing locally.

      (b) For APIs that return large JSON payloads, Holmes transforms responses into traversable
        trees with filtering and depth-limiting controls so the LLM can extract data without
        pulling the entire payload into context.

      (c) For tools that still return large outputs, HolmesGPT supports transformers that summarize
        data before it reaches the LLM.

    (2) Per-tool memory limits, streaming large results to disk, and automatic output budgeting
      prevent OOM kills when querying large observability datasets.

    (3) HolmesGPT ships with read-only integrations for every major observability vendor. Connect
      custom MCP servers for proprietary tools, or use the HTTP connector to turn any REST API into
      an LLM-friendly data source through YAML alone.

      When you need to integrate a service that doesn't have a built-in toolset, the HTTP connector
      turns raw HTTP endpoints into LLM-friendly tools through YAML configuration—no MCP servers or
      custom code required. Holmes automatically transforms these raw endpoints to be LLM-friendly.

    (4) Reconstructs upstream/downstream chains from the production data you didn't realize you
      already have. Sees the dependency graph as it actually runs, not as it was designed.

      Holmes infers service relationships from the telemetry data already flowing through your
      stack.

    (5) When Holmes queries a data source like Prometheus, the raw response data—time series, log
      entries, trace spans—is passed through to the client alongside the LLM's text analysis.
      Supported clients render this data as interactive HTML and JavaScript visualizations in a
      sandboxed environment: metric graphs with tooltips, legends, and zoom; sortable log tables
      with severity coloring and CSV export; distributed trace waterfalls with timing breakdowns.

      The LLM decides what to query and how to analyze it, but the visualization itself is a
      faithful rendering of the raw data. There is no opportunity for the LLM to hallucinate values,
      misread a graph, or fabricate trends—what you see is exactly what the data source returned.

      One such supporting client is implemented by Robusta.dev. This is not open source, so won't
      be using it.

    (6) HolmesGPT can integrate into your existing workflows, by automatically fetching alerts and
      incidents from AlertManager, PagerDuty, OpsGenie, or more—and writing the investigation
      results back to the source.
*/
function(model, modelBaseURL, prometheusURL) {
  holmesGPT: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Utils.withNamespace(app, Helm.template(app, Utils.chartsDir('holmes', std.thisFile), {
      version: '0.48.0',

      namespace: app,
      createNamespace: false,

      noHooks: true,

      values: {},
    })),
  }),
}
