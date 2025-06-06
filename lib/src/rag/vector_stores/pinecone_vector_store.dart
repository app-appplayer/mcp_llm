import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../vector_store.dart';
import '../embeddings.dart';
import '../document_store.dart';
import '../../utils/logger.dart';

/// Pinecone vector store implementation
class PineconeVectorStore implements VectorStore {
  final Logger _logger = Logger('mcp_llm.pinecone_vector_store');
  final String _apiKey;
  final String _environment;
  final String _projectId;
  final String? _baseUrl;
  final String? _defaultIndex;
  final int _dimension;
  final HttpClient _httpClient = HttpClient();
  final Map<String, dynamic> _options;

  bool _initialized = false;

  /// Create a new Pinecone vector store
  PineconeVectorStore({
    required String apiKey,
    required String environment,
    required String projectId,
    String? baseUrl,
    String? defaultIndex,
    int dimension = 1536,
    Map<String, dynamic> options = const {},
  }) : _apiKey = apiKey,
        _environment = environment,
        _projectId = projectId,
        _baseUrl = baseUrl,
        _defaultIndex = defaultIndex,
        _dimension = dimension,
        _options = options;

  /// Construct the base API URL
  String get _apiHost {
    if (_baseUrl != null) return _baseUrl;
    return 'https://controller.$_environment.pinecone.io';
  }

  /// Get the URL for a specific index
  String _getIndexUrl(String indexName) {
    return 'https://$indexName-$_projectId.svc.$_environment.pinecone.io';
  }

  @override
  Future<void> initialize() async {
    try {
      _logger.info('Initializing Pinecone vector store');

      // Check connection by listing indexes
      await listNamespaces();

      _initialized = true;
      _logger.info('Pinecone vector store initialized successfully');
    } catch (e) {
      _logger.error('Failed to initialize Pinecone vector store: $e');
      throw Exception('Failed to initialize Pinecone vector store: $e');
    }
  }

  /// Check if store is initialized
  void _checkInitialized() {
    if (!_initialized) {
      throw StateError('Pinecone vector store is not initialized');
    }
  }

  @override
  Future<void> storeEmbedding(String id, Embedding embedding, {
    Map<String, dynamic> metadata = const {},
    String? namespace,
  }) async {
    _checkInitialized();

    final indexName = namespace ?? _defaultIndex;
    if (indexName == null) {
      throw ArgumentError('No index specified and no default index configured');
    }

    try {
      final url = Uri.parse('${_getIndexUrl(indexName)}/vectors/upsert');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      final vectors = [{
        'id': id,
        'values': embedding.vector,
        if (metadata.isNotEmpty) 'metadata': metadata,
      }];

      final body = jsonEncode({
        'vectors': vectors,
        'namespace': namespace,
      });

      request.write(body);

      final response = await request.close();
      await _checkResponse(response);

      _logger.debug('Stored embedding with ID: $id in index: $indexName');
    } catch (e) {
      _logger.error('Failed to store embedding: $e');
      throw Exception('Failed to store embedding: $e');
    }
  }

  @override
  Future<void> storeEmbeddingBatch(Map<String, Embedding> embeddings, {
    Map<String, Map<String, dynamic>> metadata = const {},
    String? namespace,
  }) async {
    _checkInitialized();

    final indexName = namespace ?? _defaultIndex;
    if (indexName == null) {
      throw ArgumentError('No index specified and no default index configured');
    }

    try {
      final url = Uri.parse('${_getIndexUrl(indexName)}/vectors/upsert');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      final vectors = embeddings.entries.map((entry) {
        final id = entry.key;
        final embedding = entry.value;

        return {
          'id': id,
          'values': embedding.vector,
          if (metadata.containsKey(id) && metadata[id]!.isNotEmpty)
            'metadata': metadata[id],
        };
      }).toList();

      final body = jsonEncode({
        'vectors': vectors,
        'namespace': namespace,
      });

      request.write(body);

      final response = await request.close();
      await _checkResponse(response);

      _logger.debug('Stored ${embeddings.length} embeddings in batch in index: $indexName');
    } catch (e) {
      _logger.error('Failed to store embeddings in batch: $e');
      throw Exception('Failed to store embeddings in batch: $e');
    }
  }

  @override
  Future<List<ScoredEmbedding>> findSimilar(
      Embedding queryEmbedding, {
        int limit = 5,
        double? scoreThreshold,
        String? namespace,
        Map<String, dynamic> filters = const {},
      }) async {
    _checkInitialized();

    final indexName = namespace ?? _defaultIndex;
    if (indexName == null) {
      throw ArgumentError('No index specified and no default index configured');
    }

    try {
      final url = Uri.parse('${_getIndexUrl(indexName)}/query');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      final Map<String, dynamic> queryBody = {
        'vector': queryEmbedding.vector,
        'topK': limit,
        'includeValues': true,
        'includeMetadata': true,
      };

      // Add optional parameters
      if (namespace != null) {
        queryBody['namespace'] = namespace;
      }

      if (scoreThreshold != null) {
        queryBody['minScore'] = scoreThreshold;
      }

      if (filters.isNotEmpty) {
        queryBody['filter'] = filters;
      }

      final body = jsonEncode(queryBody);
      request.write(body);

      final response = await request.close();
      final responseBody = await _readResponseBody(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
        final matches = jsonResponse['matches'] as List<dynamic>;

        final results = matches.map((match) {
          final id = match['id'] as String;
          final score = match['score'] as double;
          final values = (match['values'] as List<dynamic>).cast<double>();
          final metadata = match['metadata'] as Map<String, dynamic>? ?? {};

          return ScoredEmbedding(
            id: id,
            embedding: Embedding(values),
            score: score,
            metadata: metadata,
          );
        }).toList();

        _logger.debug('Found ${results.length} similar embeddings in index: $indexName');
        return results;
      } else {
        throw Exception('Failed to find similar embeddings. Status: ${response.statusCode}, Body: $responseBody');
      }
    } catch (e) {
      _logger.error('Failed to find similar embeddings: $e');
      throw Exception('Failed to find similar embeddings: $e');
    }
  }

  @override
  Future<bool> deleteEmbedding(String id, {String? namespace}) async {
    _checkInitialized();

    final indexName = namespace ?? _defaultIndex;
    if (indexName == null) {
      throw ArgumentError('No index specified and no default index configured');
    }

    try {
      final url = Uri.parse('${_getIndexUrl(indexName)}/vectors/delete');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      final body = jsonEncode({
        'ids': [id],
        if (namespace != null) 'namespace': namespace,
      });

      request.write(body);

      final response = await request.close();
      await _checkResponse(response);

      _logger.debug('Deleted embedding with ID: $id from index: $indexName');
      return true;
    } catch (e) {
      _logger.error('Failed to delete embedding: $e');
      return false;
    }
  }

  @override
  Future<int> deleteEmbeddingBatch(List<String> ids, {String? namespace}) async {
    _checkInitialized();

    final indexName = namespace ?? _defaultIndex;
    if (indexName == null) {
      throw ArgumentError('No index specified and no default index configured');
    }

    if (ids.isEmpty) {
      return 0;
    }

    try {
      final url = Uri.parse('${_getIndexUrl(indexName)}/vectors/delete');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      final body = jsonEncode({
        'ids': ids,
        if (namespace != null) 'namespace': namespace,
      });

      request.write(body);

      final response = await request.close();
      await _checkResponse(response);

      _logger.debug('Deleted ${ids.length} embeddings in batch from index: $indexName');
      return ids.length;
    } catch (e) {
      _logger.error('Failed to delete embeddings in batch: $e');
      return 0;
    }
  }

  @override
  Future<bool> exists(String id, {String? namespace}) async {
    _checkInitialized();

    try {
      final embedding = await getEmbedding(id, namespace: namespace);
      return embedding != null;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Embedding?> getEmbedding(String id, {String? namespace}) async {
    _checkInitialized();

    final indexName = namespace ?? _defaultIndex;
    if (indexName == null) {
      throw ArgumentError('No index specified and no default index configured');
    }

    try {
      final url = Uri.parse('${_getIndexUrl(indexName)}/vectors/fetch');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      final body = jsonEncode({
        'ids': [id],
        if (namespace != null) 'namespace': namespace,
      });

      request.write(body);

      final response = await request.close();
      final responseBody = await _readResponseBody(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
        final vectors = jsonResponse['vectors'] as Map<String, dynamic>?;

        if (vectors == null || !vectors.containsKey(id)) {
          return null;
        }

        final vector = vectors[id] as Map<String, dynamic>;
        final values = (vector['values'] as List<dynamic>).cast<double>();

        return Embedding(values);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get embedding. Status: ${response.statusCode}, Body: $responseBody');
      }
    } catch (e) {
      _logger.error('Failed to get embedding: $e');
      throw Exception('Failed to get embedding: $e');
    }
  }

  @override
  Future<void> createNamespace(String namespace, {Map<String, dynamic> options = const {}}) async {
    _checkInitialized();

    try {
      final url = Uri.parse('$_apiHost/databases');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      // Combine default options with provided options
      final indexOptions = {
        'name': namespace,
        'dimension': _dimension, // Using _dimension field here
        'metric': _options['metric'] ?? 'cosine', // Using _options field here
        ...options,
      };

      final body = jsonEncode(indexOptions);
      request.write(body);

      final response = await request.close();
      await _checkResponse(response);

      _logger.info('Created namespace (index): $namespace');
    } catch (e) {
      _logger.error('Failed to create namespace: $e');
      throw Exception('Failed to create namespace: $e');
    }
  }

  @override
  Future<bool> deleteNamespace(String namespace) async {
    _checkInitialized();

    try {
      final url = Uri.parse('$_apiHost/databases/$namespace');

      final request = await _httpClient.deleteUrl(url);
      _setHeaders(request);

      final response = await request.close();
      await _checkResponse(response);

      _logger.info('Deleted namespace (index): $namespace');
      return true;
    } catch (e) {
      _logger.error('Failed to delete namespace: $e');
      return false;
    }
  }

  @override
  Future<List<String>> listNamespaces() async {
    _checkInitialized();

    try {
      final url = Uri.parse('$_apiHost/databases');

      final request = await _httpClient.getUrl(url);
      _setHeaders(request);

      final response = await request.close();
      final responseBody = await _readResponseBody(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonResponse = jsonDecode(responseBody) as List<dynamic>;

        final indexes = jsonResponse.map((index) {
          return (index as Map<String, dynamic>)['name'] as String;
        }).toList();

        _logger.debug('Listed ${indexes.length} namespaces (indexes)');
        return indexes;
      } else {
        throw Exception('Failed to list namespaces. Status: ${response.statusCode}, Body: $responseBody');
      }
    } catch (e) {
      _logger.error('Failed to list namespaces: $e');
      throw Exception('Failed to list namespaces: $e');
    }
  }

  @override
  Future<void> upsertDocument(Document document, {String? namespace}) async {
    _checkInitialized();

    // Validate document has an embedding
    if (document.embedding == null) {
      throw ArgumentError('Document must have an embedding');
    }

    final embedding = Embedding(document.embedding!);

    // Build metadata from document
    final metadata = {
      'title': document.title,
      'content': document.content,
      'updated_at': document.updatedAt.toIso8601String(),
      ...document.metadata,
    };

    // Store embedding with document metadata
    await storeEmbedding(
      document.id,
      embedding,
      metadata: metadata,
      namespace: namespace,
    );
  }

  @override
  Future<void> upsertDocumentBatch(List<Document> documents, {String? namespace}) async {
    _checkInitialized();

    // Filter documents with embeddings
    final validDocuments = documents.where((doc) => doc.embedding != null).toList();

    if (validDocuments.isEmpty) {
      _logger.warning('No valid documents with embeddings to upsert');
      return;
    }

    // Build maps for batch upsert
    final embeddings = <String, Embedding>{};
    final metadata = <String, Map<String, dynamic>>{};

    for (final doc in validDocuments) {
      embeddings[doc.id] = Embedding(doc.embedding!);

      metadata[doc.id] = {
        'title': doc.title,
        'content': doc.content,
        'updated_at': doc.updatedAt.toIso8601String(),
        ...doc.metadata,
      };
    }

    // Batch upsert
    await storeEmbeddingBatch(
      embeddings,
      metadata: metadata,
      namespace: namespace,
    );
  }

  @override
  Future<Document?> getDocument(String id, {String? namespace}) async {
    _checkInitialized();

    try {
      // Fetch the vector
      final indexName = namespace ?? _defaultIndex;
      if (indexName == null) {
        throw ArgumentError('No index specified and no default index configured');
      }

      final url = Uri.parse('${_getIndexUrl(indexName)}/vectors/fetch');

      final request = await _httpClient.postUrl(url);
      _setHeaders(request);

      final body = jsonEncode({
        'ids': [id],
        if (namespace != null) 'namespace': namespace,
      });

      request.write(body);

      final response = await request.close();
      final responseBody = await _readResponseBody(response);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
        final vectors = jsonResponse['vectors'] as Map<String, dynamic>?;

        if (vectors == null || !vectors.containsKey(id)) {
          return null;
        }

        final vector = vectors[id] as Map<String, dynamic>;
        final values = (vector['values'] as List<dynamic>).cast<double>();
        final metadata = vector['metadata'] as Map<String, dynamic>? ?? {};

        // Extract document fields from metadata
        final title = metadata['title'] as String? ?? 'Untitled';
        final content = metadata['content'] as String? ?? '';
        final updatedAtStr = metadata['updated_at'] as String?;

        // Create a copy of metadata without document fields
        final docMetadata = Map<String, dynamic>.from(metadata);
        docMetadata.remove('title');
        docMetadata.remove('content');
        docMetadata.remove('updated_at');

        return Document(
          id: id,
          title: title,
          content: content,
          embedding: values,
          metadata: docMetadata,
          collectionId: namespace,
          updatedAt: updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now(),
        );
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get document. Status: ${response.statusCode}, Body: $responseBody');
      }
    } catch (e) {
      _logger.error('Failed to get document: $e');
      throw Exception('Failed to get document: $e');
    }
  }

  @override
  Future<List<ScoredDocument>> findSimilarDocuments(
      Embedding queryEmbedding, {
        int limit = 5,
        double? scoreThreshold,
        String? namespace,
        Map<String, dynamic> filters = const {},
      }) async {
    _checkInitialized();

    // Find similar vectors
    final results = await findSimilar(
      queryEmbedding,
      limit: limit,
      scoreThreshold: scoreThreshold,
      namespace: namespace,
      filters: filters,
    );

    // Convert to ScoredDocument objects
    return results.map((result) {
      // Extract document fields from metadata
      final metadata = result.metadata;
      final title = metadata['title'] as String? ?? 'Untitled';
      final content = metadata['content'] as String? ?? '';
      final updatedAtStr = metadata['updated_at'] as String?;

      // Create a copy of metadata without document fields
      final docMetadata = Map<String, dynamic>.from(metadata);
      docMetadata.remove('title');
      docMetadata.remove('content');
      docMetadata.remove('updated_at');

      final document = Document(
        id: result.id,
        title: title,
        content: content,
        embedding: result.embedding.vector,
        metadata: docMetadata,
        collectionId: namespace,
        updatedAt: updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now(),
      );

      return ScoredDocument(document, result.score);
    }).toList();
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    _logger.info('Closed Pinecone vector store connection');
  }

  // Helper to set required headers
  void _setHeaders(HttpClientRequest request) {
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');
    request.headers.set('Api-Key', _apiKey);
  }

  // Helper to check response status
  Future<void> _checkResponse(HttpClientResponse response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await _readResponseBody(response);
      throw Exception('API request failed with status ${response.statusCode}: $body');
    }
  }

  // Helper to read response body
  Future<String> _readResponseBody(HttpClientResponse response) async {
    return await response.transform(utf8.decoder).join();
  }
}

/// Factory for creating Pinecone vector stores
class PineconeVectorStoreFactory implements VectorStoreFactory {
  @override
  VectorStore createVectorStore(Map<String, dynamic> config) {
    // Required parameters
    final apiKey = config['apiKey'] as String?;
    if (apiKey == null || apiKey.isEmpty) {
      throw ArgumentError('API key is required for Pinecone vector store');
    }

    final environment = config['environment'] as String?;
    if (environment == null || environment.isEmpty) {
      throw ArgumentError('Environment is required for Pinecone vector store');
    }

    final projectId = config['projectId'] as String?;
    if (projectId == null || projectId.isEmpty) {
      throw ArgumentError('Project ID is required for Pinecone vector store');
    }

    // Optional parameters
    final baseUrl = config['baseUrl'] as String?;
    final defaultIndex = config['defaultIndex'] as String?;
    final dimension = config['dimension'] as int? ?? 1536;
    final options = config['options'] as Map<String, dynamic>? ?? const {};

    return PineconeVectorStore(
      apiKey: apiKey,
      environment: environment,
      projectId: projectId,
      baseUrl: baseUrl,
      defaultIndex: defaultIndex,
      dimension: dimension,
      options: options,
    );
  }
}