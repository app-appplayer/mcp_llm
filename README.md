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
- 2025-03-26 MCP specification compliance (OAuth 2.1, JSON-RPC 2.0 batch, health monitoring, capability management, lifecycle control, enhanced error handling)
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

## Examples

- `example/mcp_2025_complete_example.dart` — full 2025-03-26 feature walkthrough
- `example/batch_processing_2025_example.dart` — JSON-RPC 2.0 batch processing
- `example/logging_example.dart` — unified logging
- `example/simple_test_example.dart` — minimal usage

## Support

- [Issue Tracker](https://github.com/app-appplayer/mcp_llm/issues)
- [Discussions](https://github.com/app-appplayer/mcp_llm/discussions)

## License

MIT — see [LICENSE](LICENSE).
