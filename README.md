# MCP LLM

A comprehensive Dart package for integrating Large Language Models (LLMs) with the [Model Context Protocol](https://modelcontextprotocol.io/). Provides multi-provider LLM access, MCP client/server orchestration, and Contract Layer adapters for the `mcp_bundle` ecosystem.

## Features

### LLM Providers

Text/chat:

- Claude (Anthropic)
- OpenAI
- Gemini (Google)
- Vertex AI
- Bedrock (AWS)
- Cohere
- Mistral
- Groq
- Together
- Custom (build your own)

Cloud capability providers:

- **Vision** — Google Cloud Vision, OpenAI GPT-4 Vision
- **ASR** — OpenAI Whisper, Google Cloud Speech-to-Text
- **OCR** — Google Cloud Vision OCR, AWS Textract
- **Binary storage** — AWS S3, Google Cloud Storage

### MCP Integration

- Multi-client and multi-server management
- Service routing, balancing, and pooling
- MCP spec compliance across revisions 2024-11-05 / 2025-03-26 / 2025-06-18 / 2025-11-25, with per-version capability gating
- OAuth 2.1 authentication
- Health monitoring, capability management, lifecycle control, and enhanced error handling
- Deferred Tool Loading (60–80% token reduction)
- Multi-round tool calling
- Resource Tool Bridge (`mcp_read_resource`, `mcp_list_resources`)

### Contract Layer Adapters

Implement `mcp_bundle` ports so `mcp_skill`, `mcp_profile`, `mcp_knowledge`, and `mcp_knowledge_ops` can plug `mcp_llm` providers in directly:

- `LlmPortAdapter`
- `AsrPortAdapter`
- `OcrPortAdapter`
- `VisionPortAdapter`
- `StoragePortAdapter`

### Other

- Plugin system (custom tools and prompt templates)
- RAG with document store and vector search (Pinecone, Weaviate)
- Parallel processing and aggregation
- Unified logging via Dart `logging` package

## Quick Start

```dart
import 'package:mcp_llm/mcp_llm.dart';

final provider = ClaudeProvider();
await provider.initialize(LlmConfiguration(apiKey: 'your-api-key'));

final response = await provider.complete(LlmRequest(
  messages: [LlmMessage.user('Hello!')],
));
print(response.text);
```

## Multi-Client Management

```dart
final manager = LlmClientManager();
await manager.registerClient('claude', ClaudeProvider(), config);
await manager.registerClient('openai', OpenAiProvider(), config);

final response = await manager.complete(
  clientId: 'claude',
  request: LlmRequest(messages: [LlmMessage.user('Hi')]),
);
```

## Contract Layer Usage

Bridge any `mcp_llm` provider to a `bundle.LlmPort` consumed by knowledge packages:

```dart
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_bundle/ports.dart' as bundle;

final provider = ClaudeProvider();
await provider.initialize(LlmConfiguration(apiKey: 'your-key'));

final bundle.LlmPort llmPort = LlmPortAdapter(provider);
// Pass llmPort into mcp_skill / mcp_profile / mcp_knowledge runtimes.
```

## Prompt Caching

`LlmRequest.cacheHints` carries provider-agnostic intent (what to mark
as cacheable) and each provider translates it into its own mechanism.
Per-provider default policy when `cacheHints` is `null`:

| Provider | Default | Mechanism | Notes |
|----------|:-------:|-----------|-------|
| Anthropic Claude | **ON** | `cache_control: ephemeral` markers on system, last tool, last 2 messages | length guard skips the marker when content is below the model minimum (Sonnet/Opus 1024 tok, Haiku 2048 tok) |
| Bedrock (Anthropic) | **ON** | same as direct Anthropic | Llama / Titan model families silently ignore hints |
| OpenAI | **ON (no-op)** | server-side automatic on shared prefixes ≥ 1024 tok | optional `parameters['prompt_cache_key']` partitions the cache space (e.g. per tenant) |
| Gemini | **OFF** | `cachedContent` resource (separate POST + reference) | persistent storage charge ($/min) + 32K-token minimum on Pro models — small/one-shot prompts cost more than they save. Caller manages lifecycle and forwards `parameters['cached_content']` |
| Vertex AI | **OFF** | same as Gemini, with project/region scoping | same opt-in pattern |
| Mistral / Cohere / Groq / Together | OFF (noop) | not exposed by provider | hints silently ignored |

Cache usage is surfaced on `LlmResponse.metadata` under canonical keys
so callers can compute savings without provider-specific branches:

- `LlmCacheMetadataKeys.cacheCreationTokens` — tokens written into the
  cache by this call (Anthropic only — priced higher than regular input)
- `LlmCacheMetadataKeys.cacheReadTokens` — tokens served from the cache
  (priced ~10% of regular input on Anthropic; bills as regular on
  OpenAI / Gemini)

To opt out on Anthropic / OpenAI:

```dart
final response = await provider.complete(LlmRequest(
  prompt: '...',
  cacheHints: CacheHints.none,  // explicit no-cache
));
```

To opt in on Gemini / Vertex AI: create a `cachedContent` resource via
the provider's HTTP API, then forward the resource name on subsequent
calls:

```dart
final response = await provider.complete(LlmRequest(
  prompt: '...',
  parameters: {'cached_content': 'cachedContents/abc-123'},
));
```

`provider.supportsPromptCaching` returns `true` when the provider has
any caching path; `false` for the four noop providers.

## Examples

- `example/simple_test_example.dart` — minimal LlmClient + mock MCP client usage
- `example/logging_example.dart` — unified logging via the Dart `logging` package

## Support

- [Issue Tracker](https://github.com/app-appplayer/mcp_llm/issues)
- [Discussions](https://github.com/app-appplayer/mcp_llm/discussions)

## License

MIT — see [LICENSE](LICENSE).
