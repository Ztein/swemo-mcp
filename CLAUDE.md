# swemo-mcp — Claude Code instructions

## What this is

An MCP server that wraps Sveriges Riksbank's monetary policy data API as typed
Python tools. Deployed as a demo for an **Intric** AI-assistant running in the
cloud, reachable from Intric via an **ngrok** tunnel hosted on a **Mac Mini**.

Forked from `aerugo/swemo-mcp`. Upstream remains as `upstream` remote.

## Tech stack

- Python 3.13, managed with **uv**
- **MCP Python SDK** (`mcp` ≥ 1.10, FastMCP)
- `httpx` for the Riksbank REST client, `pydantic` v2 for response models
- `python-dotenv` for local `.env` loading
- **Docker + ngrok** for deployment (`docker-compose.yml`)

## Engineering principles

These mirror the principles we use in the `doclib-mcp` project:

1. **Strict TDD when adding features.** Write the test first (RED), implement
   (GREEN), refactor. Never mock when you can test against the real thing.
2. **No silent fallbacks.** Errors propagate loudly. No `try/except` that
   swallows an error and returns a default — the caller deserves to know.
3. **Real backends in tests.** Hit the actual Riksbank API with `pytest`
   markers (e.g. `@pytest.mark.riksbank`) so external-dependency tests can be
   skipped in CI but run for real locally.
4. **Small, focused changes.** Don't refactor opportunistically. A bug fix
   doesn't need surrounding cleanup; a feature doesn't need a new abstraction.
5. **No backwards-compatibility shims for hypothetical callers.** The project
   has one consumer (Intric); change the code instead of layering shims.

## Deployment shape

```
┌─────────────────────────────┐
│ Intric (cloud)              │
└──────────────┬──────────────┘
               │ MCP streamable-http
               ▼
        ngrok HTTPS URL
               │
               ▼
┌─────────────────────────────┐
│ Mac Mini (on-prem)          │
│  docker compose:            │
│   • swemo-mcp :8809         │
│   • ngrok     :4041 dash    │
└─────────────────────────────┘
```

- Server listens on `0.0.0.0:8809` with transport `streamable-http`
  (env-controlled: `SWEMO_HOST`, `SWEMO_PORT`, `SWEMO_TRANSPORT`).
- ngrok dashboard maps to host port `4041` to avoid colliding with `doclib-mcp`
  on `4040` if both run on the same Mac Mini.
- Intric is configured to call `<ngrok-https-url>/mcp`.

## File layout

- `src/swemo_mcp/server.py` — FastMCP server, registers ~27 tools
- `src/swemo_mcp/tools/monetary_policy_tools.py` — one tool per series
- `src/swemo_mcp/services/monetary_policy_api.py` — async Riksbank client
  with exponential back-off
- `src/swemo_mcp/models.py` — pydantic v2 response models
- `src/swemo_mcp/utils/realized_merge.py` — merges realised observations
  into forecast vintages
- `Dockerfile` — `python:3.13-slim` + `uv sync --frozen --no-dev`
- `docker-compose.yml` — `swemo-mcp` + `ngrok`
- `.env.example` — template for `.env`

## Common commands

```bash
# Install / re-sync deps
uv sync

# Run locally over HTTP
uv run swemo-mcp

# Run locally over stdio (for Claude Desktop testing)
SWEMO_TRANSPORT=stdio uv run swemo-mcp

# Build & run via Docker on the Mac Mini
docker compose up -d --build

# Get the public ngrok URL after `up`
curl -s http://localhost:4041/api/tunnels | jq -r '.tunnels[0].public_url'

# Tear down
docker compose down

# Tests (when added)
uv run pytest -q
```

## Env vars

| Var | Default | Purpose |
|---|---|---|
| `SWEMO_HOST` | `0.0.0.0` | Bind address |
| `SWEMO_PORT` | `8809` | Bind port |
| `SWEMO_TRANSPORT` | `streamable-http` | Also accepts `stdio`, `sse` |
| `NGROK_AUTHTOKEN` | — | Required for the ngrok service in compose |

## When adding a new tool

1. Add the series to `src/swemo_mcp/tools/monetary_policy_tools.py` following
   the existing async signature `(policy_round: str | None = None) -> MonetaryPolicyDataResponse`.
2. Register it in `src/swemo_mcp/server.py` with `mcp.tool()(...)`.
3. The docstring **is** the LLM-facing prompt — make it useful, mention the
   series ID and what `policy_round="latest"` does.
4. Write a test that hits the real Riksbank API with a known policy round
   and verifies the response shape.

## What we don't do here

- Don't add a database, vector store, or LLM call. This MCP is a thin
  pass-through over the Riksbank REST API.
- Don't add Claude Desktop config snippets — this is deployed via ngrok for
  Intric, not run locally per-user.
- Don't change the tool function names — the LLM has been prompted against
  them and renames break behaviour silently.
