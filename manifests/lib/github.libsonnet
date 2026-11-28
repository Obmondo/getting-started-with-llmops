/*
  The one repository the alert workflow writes to, and the token it writes with.

  Two components need both : HolmesGPT, whose GitHub MCP server reads the repository while
  investigating, and Keep, whose workflow files the finished investigation as an issue through the
  REST API. Keep's workflow context carries no environment variables - `get_full_context` offers
  steps, event, consts, vars and a `secrets` map that the secret manager fills at runtime, none of
  which a manifest can populate - so the token has to be in the rendered workflow. Keeping it here
  means it is written once and read by both, rather than copied.

  The token is a fine-grained PAT scoped to this repository alone. Opening a pull request needs
  `Contents: read and write` for the branch and `Pull requests: write` for the pull request itself;
  filing an issue needs `Issues: write`.
*/
{
  owner:: 'Archisman-Mridha',
  repository:: 'getting-started-with-llmops',
  token:: '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',

  slug:: '%s/%s' % [self.owner, self.repository],
  apiURL:: 'https://api.github.com',

  // Every REST call carries these. `X-GitHub-Api-Version` pins the API version, which GitHub
  // documents as the way to keep a client from following a future breaking change.
  apiHeaders:: {
    Authorization: 'Bearer ' + $.token,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  },
}
