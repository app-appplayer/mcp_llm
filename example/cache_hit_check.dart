// Quick local verifier for the prompt-caching wiring.
//
// Sends the same > 1024-token system prompt twice in a row to the
// Anthropic API and prints the canonical cache metadata on each
// response. The first call should write into cache (creation tokens
// > 0); the second call (well within the 5-minute TTL) should read
// from it (read tokens > 0).
//
// Run:
//   ANTHROPIC_API_KEY=sk-ant-... dart run example/cache_hit_check.dart
import 'dart:io';

import 'package:mcp_llm/mcp_llm.dart';

Future<void> main() async {
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('ANTHROPIC_API_KEY env var is required.');
    exit(64);
  }

  // Build a system prompt above the Sonnet/Opus 1024-token minimum
  // so the cache_control marker is not skipped by the length guard.
  final filler = List.generate(
    400,
    (i) =>
        'Item $i: provider-agnostic cache hint experiment (mcp_llm 2.1.0).',
  ).join(' ');
  final systemPrompt =
      'You are a verbose cataloguer. Respond with one line. $filler';

  final provider = ClaudeProvider(
    apiKey: apiKey,
    model: 'claude-sonnet-4-5',
    config: LlmConfiguration(
      retryOnFailure: false,
      timeout: const Duration(seconds: 30),
    ),
  );

  Future<void> oneCall(String label, String prompt) async {
    final r = await provider.complete(LlmRequest(
      prompt: prompt,
      parameters: {'system': systemPrompt, 'max_tokens': 64},
    ));
    final created =
        r.metadata[LlmCacheMetadataKeys.cacheCreationTokens] ?? 0;
    final read = r.metadata[LlmCacheMetadataKeys.cacheReadTokens] ?? 0;
    stdout.writeln('$label  created=$created  read=$read');
  }

  await oneCall('call 1 (expect created>0, read=0)', 'first ping');
  // Stay well inside the 5-minute TTL.
  await Future<void>.delayed(const Duration(seconds: 2));
  await oneCall('call 2 (expect created=0, read>0)', 'second ping');

  await provider.close();
}
