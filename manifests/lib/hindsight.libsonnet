local Tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
      Helm = Tanka.helm.new(std.thisFile);
local CloudNativePG = import './cloudnative-pg.libsonnet';
local Kubernetes = import 'github.com/jsonnet-libs/k8s-libsonnet/1.32/main.libsonnet';
local Utils = import './utils.libsonnet';

local app = 'hindsight';

local storageBackendCredentialsSecretName = 'storage-backend-credentials';

/*
  AI agents forget everything between sessions. Every conversation starts from zero—no context
  about who you are, what you've discussed, or what the assistant has learned. This isn't just an
  implementation detail; it fundamentally limits what AI Agents can do.

  The problem is harder than it looks:

    (1) Simple vector search isn't enough — "What did Alice do last spring?" requires temporal
      reasoning, not just semantic similarity

    (2) Facts get disconnected — Knowing "Alice works at Google" and "Google is in Mountain View"
      should let you answer "Where does Alice work?" even if you never stored that directly

    (3) AI Agents need to consolidate knowledge — A coding assistant that remembers "the user
      prefers functional programming" should consolidate this into an observation and weigh it when
      making recommendations

    (4) Context matters — The same information means different things to different memory banks
      with different personalities

  Hindsight solves these problems with a memory system designed specifically for AI agents.

  Hindsight organizes knowledge into a hierarchy of facts and consolidated knowledge:

    (1) Mental Model : User-curated summaries for common queries.
      For e.g. :	"Team communication best practices"

    (2) Observation	Automatically : consolidated knowledge from facts.
      For e.g. : "User was a React enthusiast but has now switched to Vue" (captures history)

    (3) World Fact : Objective facts received.
      For e.g. : "Alice works at Google"

    (4) Experience Fact :	Bank's own actions and interactions
      For e.g. : "I recommended Python to Bob"

  During reflect, the agent checks sources in priority order:

                            Mental Models → Observations → Raw Facts.

  It does Multi-Strategy Retrieval (TEMPR); Four search strategies run in parallel.

  After memories are retained, Hindsight automatically consolidates related facts into observations
  — deduplicated, evidence-grounded beliefs that the bank has built up across many memories:

    (1) Deduplication: Overlapping facts are merged into a single durable observation instead of
      piling up as repeats

    (2) Evidence tracking: Each observation references the source memories (with exact quotes) that
      support it, plus a proof count

    (3) Continuous refinement: Observations are updated — not overwritten — when new evidence
      supports, contradicts, or extends them; history is preserved

    (4) Freshness awareness: when newer memories have been retained but not yet consolidated,
      reflect treats the affected observations as stale and verifies them against raw facts before
      relying on them

  Memory banks can be configured to shape how the agent reasons during reflect.
*/
function(model, modelBaseURL) {
  hindsight: Utils.withAppLabel(app, {
    namespace: Kubernetes.core.v1.namespace.new(app),

    installation: Utils.withNamespace(app, Helm.template(app, Utils.chartsDir(app, std.thisFile), {
      version: '0.9.1',

      namespace: app,
      createNamespace: false,

      values: {
        api: {
          env: {
            HINDSIGHT_API_LLM_PROVIDER: 'openai',
            HINDSIGHT_API_LLM_MODEL: model,
            HINDSIGHT_API_LLM_BASE_URL: modelBaseURL,

            // Dummy API key. We haven't enforced any authentication for the LLM.
            HINDSIGHT_API_LLM_API_KEY: 'not-enforced',
          },
        },

        existingSecret: storageBackendCredentialsSecretName,

        postgresql: {
          enabled: false,
          external: {
            host: '%s-rw.%s.svc.cluster.local' % [app, app],
            port: 5432,
            database: app,
            username: app,
          },
        },
      },
    })),

    storageBackend: CloudNativePG.newCluster(app, app) + {
      credentials: {
        apiVersion: 'v1',
        kind: 'Secret',
        metadata: {
          name: storageBackendCredentialsSecretName,
          namespace: app,
        },
        type: 'kubernetes.io/basic-auth',
        stringData: {
          username: app,
          password: app,

          'postgres-password': app,
        },
      },

      cluster+: {
        spec+: {
          imageName: 'ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie',

          bootstrap: {
            initdb: {
              database: app,
              owner: app,
              secret: { name: storageBackendCredentialsSecretName },
            },
          },

          postgresql: {
            extensions: [{
              name: 'pgvector',
              image: { reference: 'ghcr.io/cloudnative-pg/pgvector:0.8.6-18-trixie' },
            }],
          },
        },
      },

      database: {
        apiVersion: 'postgresql.cnpg.io/v1',
        kind: 'Database',
        metadata: {
          name: app,
          namespace: app,
        },
        spec: {
          name: app,
          owner: app,
          cluster: { name: app },
          extensions: [{ name: 'vector', version: '0.8.6' }],
        },
      },
    },
  }),
}
