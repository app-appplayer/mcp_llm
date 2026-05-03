import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../mcp_llm.dart';

/// Implementation of LLM interface for AWS Bedrock.
/// Provides access to multiple model families (Claude, Llama, Mistral, Titan).
/// Note: Requires AWS credentials and proper IAM permissions.
class BedrockProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
  final String region;
  final String model;
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.bedrock_provider');

  /// Available model aliases.
  static const Map<String, String> modelAliases = {
    'claude-3-sonnet': 'anthropic.claude-3-sonnet-20240229-v1:0',
    'claude-3-haiku': 'anthropic.claude-3-haiku-20240307-v1:0',
    'claude-3-opus': 'anthropic.claude-3-opus-20240229-v1:0',
    'claude-3.5-sonnet': 'anthropic.claude-3-5-sonnet-20240620-v1:0',
    'llama-3-70b': 'meta.llama3-70b-instruct-v1:0',
    'llama-3-8b': 'meta.llama3-8b-instruct-v1:0',
    'mistral-large': 'mistral.mistral-large-2407-v1:0',
    'mistral-small': 'mistral.mistral-small-2402-v1:0',
    'titan-text': 'amazon.titan-text-express-v1',
    'titan-embed': 'amazon.titan-embed-text-v1',
  };

  /// Default model.
  static const String defaultModel = 'anthropic.claude-3-sonnet-20240229-v1:0';

  /// Default embedding model.
  static const String embeddingModel = 'amazon.titan-embed-text-v1';

  /// Default region.
  static const String defaultRegion = 'us-east-1';

  BedrockProvider({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    required this.region,
    required this.model,
    required this.config,
  });

  /// Anthropic-on-Bedrock supports the same `cache_control` markers as
  /// the direct Anthropic API. Llama / Titan model families do not, so
  /// `_buildAnthropicRequestBody` is the only path that actually
  /// applies hints — the others silently ignore them.
  @override
  bool get supportsPromptCaching => true;

  String get _baseUrl => 'https://bedrock-runtime.$region.amazonaws.com';

  String _resolveModel(String modelName) {
    return modelAliases[modelName] ?? modelName;
  }

  /// Determine the model family from the model ID.
  String _getModelFamily(String modelId) {
    if (modelId.startsWith('anthropic.')) return 'anthropic';
    if (modelId.startsWith('meta.')) return 'meta';
    if (modelId.startsWith('mistral.')) return 'mistral';
    if (modelId.startsWith('amazon.')) return 'amazon';
    if (modelId.startsWith('ai21.')) return 'ai21';
    if (modelId.startsWith('cohere.')) return 'cohere';
    return 'unknown';
  }

  @override
  Future<T> executeWithRetry<T>(Future<T> Function() operation) async {
    if (!config.retryOnFailure) {
      return await operation();
    }

    int attempts = 0;
    Duration currentDelay = config.retryDelay;

    while (true) {
      try {
        return await operation().timeout(config.timeout);
      } catch (e, stackTrace) {
        attempts++;

        if (attempts >= config.maxRetries) {
          logger.error('Operation failed after $attempts attempts: $e');
          throw Exception('Max retry attempts reached: $e\n$stackTrace');
        }

        logger.warning('Attempt $attempts failed, retrying in ${currentDelay.inMilliseconds}ms: $e');
        await Future.delayed(currentDelay);

        if (config.useExponentialBackoff) {
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * 2)
                .clamp(0, config.maxRetryDelay.inMilliseconds),
          );
        }
      }
    }
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return await executeWithRetry(() async {
      logger.debug('Bedrock complete request with model: $model');

      final resolvedModel = _resolveModel(model);
      final requestBody = _buildRequestBody(request, resolvedModel);

      final uri = Uri.parse('$_baseUrl/model/$resolvedModel/invoke');

      final headers = await _getSignedHeaders('POST', uri, jsonEncode(requestBody));

      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;
        return _parseResponse(responseJson, resolvedModel);
      } else {
        final error = 'Bedrock API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Bedrock stream request with model: $model');

      final resolvedModel = _resolveModel(model);
      final requestBody = _buildRequestBody(request, resolvedModel);

      final uri = Uri.parse('$_baseUrl/model/$resolvedModel/invoke-with-response-stream');

      final headers = await _getSignedHeaders('POST', uri, jsonEncode(requestBody));

      final httpRequest = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(requestBody);

      final streamedResponse = await executeWithRetry(() async {
        return await _client.send(httpRequest);
      });

      if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
        final StringBuffer responseText = StringBuffer();
        List<LlmToolCall>? toolCalls;
        String? finishReason;

        final modelFamily = _getModelFamily(resolvedModel);

        await for (final chunk in streamedResponse.stream) {
          final events = _parseEventStream(chunk);

          for (final event in events) {
            if (event.containsKey('bytes')) {
              final payloadBytes = base64Decode(event['bytes'] as String);
              final payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;

              switch (modelFamily) {
                case 'anthropic':
                  final result = _parseAnthropicStreamChunk(payload, toolCalls);
                  final cacheMeta =
                      result['cacheMetadata'] as Map<String, dynamic>?;
                  if (cacheMeta != null && cacheMeta.isNotEmpty) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: false,
                      metadata: cacheMeta,
                    );
                  }
                  if (result['text'] != null) {
                    responseText.write(result['text']);
                    yield LlmResponseChunk(
                      textChunk: result['text'] as String,
                      isDone: false,
                      metadata: {},
                      toolCalls: result['toolCalls'] as List<LlmToolCall>?,
                    );
                  }
                  if (result['toolCalls'] != null) {
                    toolCalls = result['toolCalls'] as List<LlmToolCall>;
                  }
                  if (result['isDone'] == true) {
                    finishReason = result['finishReason'] as String?;
                  }
                  break;

                case 'meta':
                case 'mistral':
                  final text = _parseLlamaStreamChunk(payload);
                  if (text != null && text.isNotEmpty) {
                    responseText.write(text);
                    yield LlmResponseChunk(
                      textChunk: text,
                      isDone: false,
                      metadata: {},
                    );
                  }
                  if (payload['stop_reason'] != null) {
                    finishReason = 'stop';
                  }
                  break;

                case 'amazon':
                  final text = _parseTitanStreamChunk(payload);
                  if (text != null && text.isNotEmpty) {
                    responseText.write(text);
                    yield LlmResponseChunk(
                      textChunk: text,
                      isDone: false,
                      metadata: {},
                    );
                  }
                  if (payload['completionReason'] != null) {
                    finishReason = 'stop';
                  }
                  break;
              }
            }
          }
        }

        yield LlmResponseChunk(
          textChunk: '',
          isDone: true,
          metadata: {
            'finish_reason': toolCalls != null ? 'tool_calls' : (finishReason ?? 'stop'),
            if (toolCalls != null) 'expects_tool_result': true,
          },
          toolCalls: toolCalls,
        );
      } else {
        final responseBody = await utf8.decoder.bind(streamedResponse.stream).join();
        final error = 'Bedrock API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Bedrock.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      logger.error('Error streaming from Bedrock API: $e\n$stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Bedrock.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  List<Map<String, dynamic>> _parseEventStream(List<int> chunk) {
    final events = <Map<String, dynamic>>[];
    final data = utf8.decode(chunk);

    final lines = data.split('\n');
    Map<String, dynamic>? currentEvent;

    for (final line in lines) {
      if (line.startsWith(':event-type')) {
        currentEvent = {};
      } else if (line.startsWith(':content-type')) {
        continue;
      } else if (line.isNotEmpty && currentEvent != null) {
        final event = currentEvent;
        try {
          final parsed = jsonDecode(line) as Map<String, dynamic>;
          event.addAll(parsed);
          events.add(event);
        } catch (_) {
          event['bytes'] = line;
          events.add(event);
        }
        currentEvent = null;
      }
    }

    return events;
  }

  Map<String, dynamic> _parseAnthropicStreamChunk(
      Map<String, dynamic> payload, List<LlmToolCall>? existingToolCalls) {
    final result = <String, dynamic>{};

    final type = payload['type'] as String?;

    switch (type) {
      case 'message_start':
        // Surface prompt-cache usage from `message.usage` so streaming
        // callers can observe cache hits via response chunk metadata.
        final msg = payload['message'];
        if (msg is Map<String, dynamic>) {
          final usage = msg['usage'];
          if (usage is Map<String, dynamic>) {
            final cacheMeta = <String, dynamic>{};
            final created = usage['cache_creation_input_tokens'];
            final read = usage['cache_read_input_tokens'];
            if (created is int) {
              cacheMeta[LlmCacheMetadataKeys.cacheCreationTokens] = created;
            }
            if (read is int) {
              cacheMeta[LlmCacheMetadataKeys.cacheReadTokens] = read;
            }
            if (cacheMeta.isNotEmpty) {
              result['cacheMetadata'] = cacheMeta;
            }
          }
        }
        break;

      case 'content_block_delta':
        final delta = payload['delta'] as Map<String, dynamic>?;
        if (delta != null) {
          if (delta['type'] == 'text_delta') {
            result['text'] = delta['text'] as String?;
          } else if (delta['type'] == 'input_json_delta') {
            final partialJson = delta['partial_json'] as String?;
            if (partialJson != null) {
              result['partialToolArgs'] = partialJson;
            }
          }
        }
        break;

      case 'content_block_start':
        final contentBlock = payload['content_block'] as Map<String, dynamic>?;
        if (contentBlock != null && contentBlock['type'] == 'tool_use') {
          final toolCalls = existingToolCalls ?? [];
          final toolId = contentBlock['id'] as String;
          final toolName = contentBlock['name'] as String;

          toolCalls.add(LlmToolCall(
            id: toolId,
            name: toolName,
            arguments: {},
          ));

          result['toolCalls'] = toolCalls;
        }
        break;

      case 'message_delta':
        final delta = payload['delta'] as Map<String, dynamic>?;
        if (delta != null) {
          result['finishReason'] = delta['stop_reason'] as String?;
          result['isDone'] = true;
        }
        break;

      case 'message_stop':
        result['isDone'] = true;
        break;
    }

    return result;
  }

  String? _parseLlamaStreamChunk(Map<String, dynamic> payload) {
    return payload['generation'] as String?;
  }

  String? _parseTitanStreamChunk(Map<String, dynamic> payload) {
    return payload['outputText'] as String?;
  }

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    if (metadata.containsKey('tool_call_start') && metadata['tool_call_start'] == true) {
      return true;
    }

    if (metadata.containsKey('finish_reason') && metadata['finish_reason'] == 'tool_calls') {
      return true;
    }

    final toolKeys = ['tool_call_id', 'tool_calls', 'tool_call_update'];
    for (final key in toolKeys) {
      if (metadata.containsKey(key)) {
        return true;
      }
    }

    return false;
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    if ((metadata.containsKey('tool_call_start') || metadata.containsKey('tool_call_update')) &&
        (metadata.containsKey('tool_name') || metadata.containsKey('tool_call_id'))) {
      final toolName = metadata['tool_name'] as String? ?? 'unknown_tool';
      final toolId = metadata['tool_call_id'] as String? ??
          'bedrock_tool_${DateTime.now().millisecondsSinceEpoch}';

      Map<String, dynamic> arguments = {};

      if (metadata.containsKey('tool_call_args') &&
          metadata['tool_call_args'] is Map<String, dynamic>) {
        arguments = metadata['tool_call_args'] as Map<String, dynamic>;
      }

      return LlmToolCall(
        id: toolId,
        name: toolName,
        arguments: arguments,
      );
    }

    return null;
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    final standardMetadata = Map<String, dynamic>.from(metadata);

    if (metadata.containsKey('finish_reason') && metadata['finish_reason'] == 'tool_calls') {
      if (!standardMetadata.containsKey('expects_tool_result')) {
        standardMetadata['expects_tool_result'] = true;
      }
    }

    if (metadata.containsKey('tool_call_start') && metadata['tool_call_start'] == true) {
      standardMetadata['is_tool_call'] = true;
    }

    if (metadata.containsKey('tool_call_id') && !standardMetadata.containsKey('tool_id')) {
      standardMetadata['tool_id'] = metadata['tool_call_id'];
    }

    return standardMetadata;
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return await executeWithRetry(() async {
      logger.debug('Bedrock embeddings request');

      final uri = Uri.parse('$_baseUrl/model/$embeddingModel/invoke');

      final requestBody = {
        'inputText': text,
      };

      final headers = await _getSignedHeaders('POST', uri, jsonEncode(requestBody));

      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;

        final embedding = responseJson['embedding'] as List<dynamic>?;
        if (embedding != null && embedding.isNotEmpty) {
          return embedding.map((e) => (e as num).toDouble()).toList();
        } else {
          throw StateError('No embedding data returned from Bedrock API');
        }
      } else {
        final error = 'Bedrock API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('Bedrock provider initialized with model: $model, region: $region');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Bedrock provider client closed');
  }

  /// Get headers with AWS Signature Version 4.
  /// Note: This is a simplified implementation. For production use,
  /// consider using the aws_signature_v4 package.
  Future<Map<String, String>> _getSignedHeaders(
      String method, Uri uri, String body) async {
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Amz-Date': amzDate,
      'Host': uri.host,
    };

    if (sessionToken != null) {
      headers['X-Amz-Security-Token'] = sessionToken!;
    }

    final credentialScope = '$dateStamp/$region/bedrock/aws4_request';
    final signedHeaders = headers.keys.map((k) => k.toLowerCase()).toList()..sort();

    final canonicalRequest = _buildCanonicalRequest(
      method,
      uri,
      headers,
      signedHeaders,
      body,
    );

    final stringToSign = _buildStringToSign(amzDate, credentialScope, canonicalRequest);
    final signature = _calculateSignature(dateStamp, stringToSign);

    final authHeader = 'AWS4-HMAC-SHA256 '
        'Credential=$accessKeyId/$credentialScope, '
        'SignedHeaders=${signedHeaders.join(';')}, '
        'Signature=$signature';

    headers['Authorization'] = authHeader;

    return headers;
  }

  String _formatDateStamp(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  String _formatAmzDate(DateTime date) {
    return '${_formatDateStamp(date)}T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}Z';
  }

  String _buildCanonicalRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    List<String> signedHeaders,
    String body,
  ) {
    final canonicalUri = uri.path.isEmpty ? '/' : uri.path;
    final canonicalQueryString = uri.query;

    final canonicalHeaders = StringBuffer();
    for (final header in signedHeaders) {
      final headerKey = _findHeader(headers, header);
      final headerValue = headerKey != null ? headers[headerKey] : '';
      canonicalHeaders.write('$header:$headerValue\n');
    }

    final payloadHash = _sha256Hash(body);

    return '$method\n'
        '$canonicalUri\n'
        '$canonicalQueryString\n'
        '${canonicalHeaders.toString()}\n'
        '${signedHeaders.join(';')}\n'
        '$payloadHash';
  }

  String? _findHeader(Map<String, String> headers, String lowerKey) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerKey) {
        return entry.key;
      }
    }
    return null;
  }

  String _buildStringToSign(String amzDate, String credentialScope, String canonicalRequest) {
    return 'AWS4-HMAC-SHA256\n'
        '$amzDate\n'
        '$credentialScope\n'
        '${_sha256Hash(canonicalRequest)}';
  }

  String _calculateSignature(String dateStamp, String stringToSign) {
    final kDate = _hmacSha256('AWS4$secretAccessKey', dateStamp);
    final kRegion = _hmacSha256Bytes(kDate, region);
    final kService = _hmacSha256Bytes(kRegion, 'bedrock');
    final kSigning = _hmacSha256Bytes(kService, 'aws4_request');
    return _hmacSha256BytesHex(kSigning, stringToSign);
  }

  String _sha256Hash(String data) {
    final bytes = utf8.encode(data);
    final digest = _sha256(bytes);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  List<int> _sha256(List<int> data) {
    const k = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final padded = _padMessage(data);

    for (var i = 0; i < padded.length; i += 64) {
      final w = List<int>.filled(64, 0);

      for (var j = 0; j < 16; j++) {
        w[j] = (padded[i + j * 4] << 24) |
            (padded[i + j * 4 + 1] << 16) |
            (padded[i + j * 4 + 2] << 8) |
            padded[i + j * 4 + 3];
      }

      for (var j = 16; j < 64; j++) {
        final s0 = _rotr(w[j - 15], 7) ^ _rotr(w[j - 15], 18) ^ (w[j - 15] >> 3);
        final s1 = _rotr(w[j - 2], 17) ^ _rotr(w[j - 2], 19) ^ (w[j - 2] >> 10);
        w[j] = (w[j - 16] + s0 + w[j - 7] + s1) & 0xFFFFFFFF;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (var j = 0; j < 64; j++) {
        final sigma1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final temp1 = (h + sigma1 + ch + k[j] + w[j]) & 0xFFFFFFFF;
        final sigma0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (sigma0 + maj) & 0xFFFFFFFF;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h0 = (h0 + a) & 0xFFFFFFFF;
      h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF;
      h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF;
      h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF;
      h7 = (h7 + h) & 0xFFFFFFFF;
    }

    return [
      ..._intToBytes(h0),
      ..._intToBytes(h1),
      ..._intToBytes(h2),
      ..._intToBytes(h3),
      ..._intToBytes(h4),
      ..._intToBytes(h5),
      ..._intToBytes(h6),
      ..._intToBytes(h7),
    ];
  }

  List<int> _padMessage(List<int> data) {
    final len = data.length;
    final bitLen = len * 8;

    final padded = [...data, 0x80];

    while ((padded.length % 64) != 56) {
      padded.add(0);
    }

    for (var i = 7; i >= 0; i--) {
      padded.add((bitLen >> (i * 8)) & 0xFF);
    }

    return padded;
  }

  int _rotr(int x, int n) {
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;
  }

  List<int> _intToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  List<int> _hmacSha256(String key, String data) {
    return _hmacSha256Bytes(utf8.encode(key), data);
  }

  List<int> _hmacSha256Bytes(List<int> key, String data) {
    const blockSize = 64;

    var keyBytes = key;
    if (keyBytes.length > blockSize) {
      keyBytes = _sha256(keyBytes);
    }
    if (keyBytes.length < blockSize) {
      keyBytes = [...keyBytes, ...List<int>.filled(blockSize - keyBytes.length, 0)];
    }

    final oKeyPad = keyBytes.map((b) => b ^ 0x5c).toList();
    final iKeyPad = keyBytes.map((b) => b ^ 0x36).toList();

    final innerHash = _sha256([...iKeyPad, ...utf8.encode(data)]);
    return _sha256([...oKeyPad, ...innerHash]);
  }

  String _hmacSha256BytesHex(List<int> key, String data) {
    final hash = _hmacSha256Bytes(key, data);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, dynamic> _buildRequestBody(LlmRequest request, String modelId) {
    final modelFamily = _getModelFamily(modelId);

    switch (modelFamily) {
      case 'anthropic':
        return _buildAnthropicRequestBody(request);
      case 'meta':
      case 'mistral':
        return _buildLlamaRequestBody(request);
      case 'amazon':
        return _buildTitanRequestBody(request);
      default:
        return _buildAnthropicRequestBody(request);
    }
  }

  Map<String, dynamic> _buildAnthropicRequestBody(LlmRequest request) {
    final List<Map<String, dynamic>> messages = [];
    String? systemContent;

    if (request.parameters.containsKey('system') ||
        request.parameters.containsKey('system_instructions')) {
      systemContent = request.parameters['system'] ??
          request.parameters['system_instructions'];
    }

    for (final message in request.history) {
      if (message.role == 'system') {
        if (systemContent == null || systemContent.isEmpty) {
          systemContent = message.content.toString();
        }
        continue;
      }

      final role = message.role == 'assistant' ? 'assistant' : 'user';

      if (message.role == 'tool') {
        final toolContent = message.content;
        if (toolContent is Map) {
          messages.add({
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': toolContent['tool_call_id'] ?? message.metadata['tool_call_id'],
                'content': toolContent['content'] ?? toolContent.toString(),
              }
            ],
          });
        }
        continue;
      }

      messages.add({
        'role': role,
        'content': message.content.toString(),
      });
    }

    messages.add({
      'role': 'user',
      'content': request.prompt,
    });

    final body = <String, dynamic>{
      'anthropic_version': 'bedrock-2023-05-31',
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
      'messages': messages,
    };

    // Anthropic on Bedrock honours the same `cache_control` markers as
    // the direct Anthropic API. Apply hints with the same default-ON
    // policy and length guard.
    final hints = request.cacheHints ?? CacheHints.all;

    if (systemContent != null && systemContent.isNotEmpty) {
      if (hints.system && _meetsBedrockAnthropicCacheMinimum(systemContent)) {
        body['system'] = [
          {
            'type': 'text',
            'text': systemContent,
            'cache_control': {'type': 'ephemeral'},
          }
        ];
      } else {
        body['system'] = systemContent;
      }
    }

    if (request.parameters.containsKey('temperature')) {
      body['temperature'] = request.parameters['temperature'];
    }

    if (request.parameters.containsKey('tools')) {
      final tools = request.parameters['tools'] as List<dynamic>;
      final claudeTools = tools.map((tool) {
        return {
          'name': tool['name'],
          'description': tool['description'],
          'input_schema': tool['parameters'],
        };
      }).toList();
      if (hints.tools && claudeTools.isNotEmpty) {
        claudeTools.last['cache_control'] = {'type': 'ephemeral'};
      }
      body['tools'] = claudeTools;
    }

    if (hints.messages > 0 && messages.isNotEmpty) {
      // Anthropic-on-Bedrock shares the 4-breakpoint limit. Cap
      // message marks at the remaining budget after system + tools.
      final budget = 4 -
          (body['system'] is List ? 1 : 0) -
          (hints.tools && body['tools'] is List ? 1 : 0);
      final messageCount =
          hints.messages > budget ? budget : hints.messages;
      if (messageCount > 0) {
        _markBedrockMessageCacheBreakpoints(messages, messageCount);
      }
    }

    return body;
  }

  /// Anthropic-on-Bedrock minimum-cacheable size guard. Mirrors the
  /// direct Anthropic API tiering (Haiku 2048, others 1024).
  bool _meetsBedrockAnthropicCacheMinimum(String content) {
    final approxTokens = (content.length / 4).ceil();
    final minimum = model.toLowerCase().contains('haiku') ? 2048 : 1024;
    return approxTokens >= minimum;
  }

  void _markBedrockMessageCacheBreakpoints(
      List<Map<String, dynamic>> messages, int count) {
    var marked = 0;
    for (var i = messages.length - 1; i >= 0 && marked < count; i--) {
      final msg = messages[i];
      final content = msg['content'];
      if (content is String) {
        if (content.isEmpty) continue;
        msg['content'] = [
          {
            'type': 'text',
            'text': content,
            'cache_control': {'type': 'ephemeral'},
          }
        ];
        marked++;
      } else if (content is List && content.isNotEmpty) {
        final last = content.last;
        if (last is Map<String, dynamic> && _isBedrockMarkableBlock(last)) {
          last['cache_control'] = {'type': 'ephemeral'};
          marked++;
        }
      }
    }
  }

  /// Anthropic-on-Bedrock has the same empty-text restriction as the
  /// direct Anthropic API.
  bool _isBedrockMarkableBlock(Map<String, dynamic> block) {
    final type = block['type'];
    if (type != 'text') return true;
    final text = block['text'];
    return text is String && text.isNotEmpty;
  }

  Map<String, dynamic> _buildLlamaRequestBody(LlmRequest request) {
    final StringBuffer prompt = StringBuffer();

    String? systemContent;
    if (request.parameters.containsKey('system')) {
      systemContent = request.parameters['system'];
    }

    for (final message in request.history) {
      if (message.role == 'system') {
        systemContent ??= message.content.toString();
        continue;
      }

      if (message.role == 'user') {
        prompt.write('[INST] ${message.content} [/INST]\n');
      } else if (message.role == 'assistant') {
        prompt.write('${message.content}\n');
      }
    }

    if (systemContent != null) {
      prompt.write('[INST] <<SYS>>\n$systemContent\n<</SYS>>\n\n');
    }

    prompt.write('[INST] ${request.prompt} [/INST]');

    final body = <String, dynamic>{
      'prompt': prompt.toString(),
      'max_gen_len': request.parameters['max_tokens'] ?? 1024,
      'top_p': request.parameters['top_p'] ?? 0.9,
    };
    if (request.parameters['temperature'] != null) {
      body['temperature'] = request.parameters['temperature'];
    }
    return body;
  }

  Map<String, dynamic> _buildTitanRequestBody(LlmRequest request) {
    final StringBuffer inputText = StringBuffer();

    for (final message in request.history) {
      if (message.role == 'user') {
        inputText.write('User: ${message.content}\n');
      } else if (message.role == 'assistant') {
        inputText.write('Bot: ${message.content}\n');
      }
    }

    inputText.write('User: ${request.prompt}\nBot:');

    final config = <String, dynamic>{
      'maxTokenCount': request.parameters['max_tokens'] ?? 1024,
      'topP': request.parameters['top_p'] ?? 0.9,
    };
    if (request.parameters['temperature'] != null) {
      config['temperature'] = request.parameters['temperature'];
    }
    return {
      'inputText': inputText.toString(),
      'textGenerationConfig': config,
    };
  }

  LlmResponse _parseResponse(Map<String, dynamic> response, String modelId) {
    final modelFamily = _getModelFamily(modelId);

    switch (modelFamily) {
      case 'anthropic':
        return _parseAnthropicResponse(response);
      case 'meta':
      case 'mistral':
        return _parseLlamaResponse(response);
      case 'amazon':
        return _parseTitanResponse(response);
      default:
        return _parseAnthropicResponse(response);
    }
  }

  LlmResponse _parseAnthropicResponse(Map<String, dynamic> response) {
    String text = '';
    List<LlmToolCall>? toolCalls;
    String? finishReason = response['stop_reason'] as String?;

    final content = response['content'] as List<dynamic>?;
    if (content != null) {
      final textParts = StringBuffer();
      for (final block in content) {
        if (block is Map<String, dynamic>) {
          if (block['type'] == 'text') {
            textParts.write(block['text']);
          } else if (block['type'] == 'tool_use') {
            toolCalls ??= [];
            toolCalls.add(LlmToolCall(
              id: block['id'] as String,
              name: block['name'] as String,
              arguments: block['input'] as Map<String, dynamic>? ?? {},
            ));
          }
        }
      }
      text = textParts.toString();
    }

    final metadata = <String, dynamic>{
      'model': model,
      'finish_reason': toolCalls != null ? 'tool_calls' : (finishReason ?? 'stop'),
      'provider': 'bedrock',
      'region': region,
    };

    if (response.containsKey('usage')) {
      metadata['usage'] = response['usage'];
      final usage = response['usage'];
      if (usage is Map<String, dynamic>) {
        final created = usage['cache_creation_input_tokens'];
        final read = usage['cache_read_input_tokens'];
        if (created is int) {
          metadata[LlmCacheMetadataKeys.cacheCreationTokens] = created;
        }
        if (read is int) {
          metadata[LlmCacheMetadataKeys.cacheReadTokens] = read;
        }
      }
    }

    if (toolCalls != null && toolCalls.isNotEmpty) {
      metadata['tool_call_ids'] = toolCalls.map((tc) => tc.id).toList();
      metadata['expects_tool_result'] = true;
    }

    return LlmResponse(
      text: text,
      metadata: metadata,
      toolCalls: toolCalls,
    );
  }

  LlmResponse _parseLlamaResponse(Map<String, dynamic> response) {
    final text = response['generation'] as String? ?? '';

    final metadata = <String, dynamic>{
      'model': model,
      'finish_reason': response['stop_reason'] ?? 'stop',
      'provider': 'bedrock',
      'region': region,
    };

    return LlmResponse(
      text: text,
      metadata: metadata,
    );
  }

  LlmResponse _parseTitanResponse(Map<String, dynamic> response) {
    String text = '';

    final results = response['results'] as List<dynamic>?;
    if (results != null && results.isNotEmpty) {
      text = results.first['outputText'] as String? ?? '';
    }

    final metadata = <String, dynamic>{
      'model': model,
      'finish_reason': response['completionReason'] ?? 'stop',
      'provider': 'bedrock',
      'region': region,
    };

    return LlmResponse(
      text: text,
      metadata: metadata,
    );
  }
}

/// Factory for creating Bedrock providers.
class BedrockProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'bedrock';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.embeddings,
    LlmCapability.toolUse,
    LlmCapability.functionCalling,
    LlmCapability.imageUnderstanding,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final options = config.options ?? {};

    final accessKeyId = options['access_key_id'] as String?;
    final secretAccessKey = options['secret_access_key'] as String?;

    if (accessKeyId == null || accessKeyId.isEmpty) {
      throw StateError('access_key_id is required in options for Bedrock provider');
    }
    if (secretAccessKey == null || secretAccessKey.isEmpty) {
      throw StateError('secret_access_key is required in options for Bedrock provider');
    }

    final region = options['region'] as String? ?? BedrockProvider.defaultRegion;
    final sessionToken = options['session_token'] as String?;

    return BedrockProvider(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
      region: region,
      model: config.model ?? BedrockProvider.defaultModel,
      config: config,
    );
  }
}
