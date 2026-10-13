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
- Every MCP revision the connected mcp_client / mcp_server speaks (2024-11-05 through 2026-07-28); MCP values are the protocol's generated types (`package:mcp_llm/mcp_types.dart`)
- Authorization through the MCP client (`McpOAuth` in mcp_client)
- Typed MCP layer: every listing page, tool results rendered by content kind, sampling answered by a provider
- Tool calls run with the arguments the model gave, each keeping one id from the model's turn to its result
- Images and stop sequences sent in each provider's API format
- Per-peer records: declared capabilities, health (`ping` for a client, the server's health record for a server), lifecycle state
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

Future<void> main() async {
  final provider = ClaudeProvider(
    apiKey: 'your-api-key',
    model: 'claude-sonnet-5-5',
    config: LlmConfiguration(apiKey: 'your-api-key', model: 'claude-sonnet-5-5'),
  );

  final response = await provider.complete(LlmRequest(prompt: 'Hello!'));
  print(response.text);
}
```

Through the registry, by provider name:

```dart
final mcpLlm = McpLlm()..registerProvider('claude', ClaudeProviderFactory());
final client = await mcpLlm.createClient(
  providerName: 'claude',
  config: LlmConfiguration(apiKey: 'your-api-key', model: 'claude-sonnet-5-5'),
);
final reply = await client.chat('Hello!');
print(reply.text);
```

## Using an MCP Server's Tools

Hand `LlmClient` a connected mcp_client; `chat(enableTools: true)` offers the
server's tools to the model, runs the calls it makes and returns the final
answer. Tool results reach the model rendered by content kind (`isError`
marked, `structuredContent` as JSON).

```dart
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:mcp_llm/mcp_llm.dart';

Future<void> withTools(LlmProvider provider) async {
  final mcpClient = mcp.McpClient.createClient(mcp.McpClient.simpleConfig(name: 'host', version: '1.0.0'));
  await mcpClient.connect(await mcp.StdioClientTransport.create(command: 'my-mcp-server'));

  final llm = LlmClient(llmProvider: provider, mcpClient: mcpClient);
  final answer = await llm.chat('What is in my calendar today?', enableTools: true);
  print(answer.text);

  // Typed access to the server, every page of every list:
  final tools = await McpClientBridge(mcpClient).listTools();
  print(tools.map((t) => t.name));
}
```

The server's `sampling/createMessage` requests can be answered by a
provider: `LlmClientAdapter(mcpClient).bindSamplingToLlm(provider, model: 'claude-sonnet-5-5')`
on a client created with `ClientCapabilities(sampling: true)`.

## Multi-Client Management

```dart
final manager = MultiLlmClientManager(loadBalancer: DefaultServiceBalancer());
manager.addClient('claude', claudeClient, weight: 2);
manager.addClient('openai', openAiClient);

final client = manager.selectClient('summarize this');
final response = await client?.chat('Summarize: ...');
```

## Contract Layer Usage

Bridge any `mcp_llm` provider to a `bundle.LlmPort` consumed by knowledge packages:

```dart
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_bundle/ports.dart' as bundle;

bundle.LlmPort portFor(LlmProvider provider) => LlmPortAdapter(provider);
// Pass the port into mcp_skill / mcp_profile / mcp_knowledge runtimes.
```

## Prompt Caching

`LlmRequest.cacheHints` carries provider-agnostic intent (what to mark
as cacheable) and each provider translates it into its own mechanism.
Per-provider default policy when `cacheHints` is `null`:

| Provider | Default | Mechanism | Notes |
|----------|:-------:|-----------|-------|
| Anthropic Claude | **ON** | `cache_control: ephemeral` markers on system, last tool, last 2 messages | length guard skips the marker when content is below the model minimum (Sonnet/Opus 1024 tok, Haiku 2048 tok) |
| Bedrock (Anthropic) | **ON** | same as direct Anthropic | applies to the Anthropic model family |
| OpenAI | **ON (no-op)** | server-side automatic on shared prefixes ≥ 1024 tok | optional `parameters['prompt_cache_key']` partitions the cache space (e.g. per tenant) |
| Gemini | **OFF** | `cachedContent` resource (separate POST + reference) | persistent storage charge ($/min) + 32K-token minimum on Pro models — small/one-shot prompts cost more than they save. Caller manages lifecycle and forwards `parameters['cached_content']` |
| Vertex AI | **OFF** | same as Gemini, with project/region scoping | same opt-in pattern |
| Mistral / Cohere / Groq / Together | OFF (noop) | caching is the provider's own | hints are left to the provider |

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
