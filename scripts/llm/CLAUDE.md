# The model plumbing (`scripts/llm/`)

The root invariants rule here first: the engine decides, the model only writes words (1); its output enters the engine only as validated action codes, clamped enums and schema-listed world deltas (2); clicked suggestions and low-stakes lines never call the API (9). Model IDs and prices live in one config table (PRD §8). Test runs force offline with `CC_FORCE_OFFLINE=1`.

- **Config**: `.env` (git-ignored, read by `OpenAIClient.load_config()`; `.env.example` lists `OPENAI_API_KEY`, `LLM_MODEL` / per-tier overrides, `LLM_MAX_OUTPUT_TOKENS`) overlays the defaults and is overlaid by `user://config.json` (`api_key`, `model_parse`, `model_voice`, `model_order`, `model_flagship`, `offline_mode`). A missing or malformed file, an empty key or `CC_FORCE_OFFLINE=1` fails closed to `offline_mode: true`. The key is never committed, never shipped.
- **Raw HTTP** (`HTTPRequest`) in `openai_client.gd`; no SDK.
- **`response_validator.gd`** checks a model reply (JSON shape, action codes against the data, tone); a reply that fails comes back `ok: false` with a neutral reaction, never patched up. World deltas go through `WorldLedger` (root invariant 1).
- **Events are never model-written**: `Voicer.voice_event` has no path to the API; event prose comes from `RANDOM_EVENTS.md` and the chapter documents. `template_voicer.gd` renders the template lines that cost no call.
