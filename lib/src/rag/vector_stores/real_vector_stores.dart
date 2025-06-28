/// Real vector store implementations for production use
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../utils/logger.dart';
import '../vector_store.dart';
import '../embeddings.dart';
import '../document_store.dart';

final Logger _logger = Logger('mcp_llm.real_vector_stores');

/// Vector document for internal use
class VectorDocument {
  final String id;
  final List<double> vector;
  final Map<String, dynamic> metadata;

  VectorDocument({
    required this.id,
    required this.vector,
    required this.metadata,
  });
}

/// Vector search result for internal use
class VectorSearchResult {
  final String id;
  final double score;
  final List<double>? vector;
  final Map<String, dynamic> metadata;

  VectorSearchResult({
    required this.id,
    required this.score,
    this.vector,
    required this.metadata,
  });
}

/// Vector store statistics
class VectorStoreStats {
  final int totalVectors;
  final int dimensions;
  final List<String> namespaces;

  VectorStoreStats({
    required this.totalVectors,
    required this.dimensions,
    required this.namespaces,
  });
}

/// Pinecone vector store implementation
class RealPineconeVectorStore implements VectorStore {
  final String apiKey;
  final String environment;
  final String indexName;
  final int dimension;
  final http.Client _httpClient;
  
  late String _baseUrl;
  bool _initialized = false;

  RealPineconeVectorStore({
    required this.apiKey,
    required this.environment,
    required this.indexName,
    required this.dimension,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client() {
    _baseUrl = 'https://$indexName-$environment.svc.pinecone.io';
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Test connection by getting index stats
      await _makeRequest('GET', '/describe_index_stats');
      _initialized = true;
      _logger.info('Pinecone vector store initialized: $indexName');
    } catch (e) {
      throw Exception('Failed to initialize Pinecone vector store: $e');
    }
  }

  @override
  Future<void> storeEmbedding(String id, Embedding embedding, {
    Map<String, dynamic> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();
    final doc = VectorDocument(
      id: id,
      vector: embedding.vector,
      metadata: metadata,
    );
    await _upsertBatch(namespace ?? 'default', [doc]);
    _logger.debug('Stored embedding $id in namespace: ${namespace ?? 'default'}');
  }

  @override
  Future<void> storeEmbeddingBatch(Map<String, Embedding> embeddings, {
    Map<String, Map<String, dynamic>> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();
    final documents = embeddings.entries.map((entry) {
      return VectorDocument(
        id: entry.key,
        vector: entry.value.vector,
        metadata: metadata[entry.key] ?? {},
      );
    }).toList();
    
    // Split into batches of 100 documents (Pinecone limit)
    const batchSize = 100;
    for (int i = 0; i < documents.length; i += batchSize) {
      final batch = documents.skip(i).take(batchSize).toList();
      await _upsertBatch(namespace ?? 'default', batch);
    }
    
    _logger.debug('Stored ${documents.length} embeddings in namespace: ${namespace ?? 'default'}');
  }

  @override
  Future<List<ScoredEmbedding>> findSimilar(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    await _ensureInitialized();

    final body = <String, dynamic>{
      'vector': queryEmbedding.vector,
      'topK': limit,
      'namespace': namespace ?? 'default',
      'includeMetadata': true,
      'includeValues': true,
    };

    if (filters.isNotEmpty) {
      body['filter'] = filters;
    }

    final response = await _makeRequest('POST', '/query', body: body);
    final matches = response['matches'] as List<dynamic>;

    return matches
        .where((match) => scoreThreshold == null || (match['score'] as num).toDouble() >= scoreThreshold)
        .map((match) => ScoredEmbedding(
              id: match['id'] as String,
              embedding: Embedding((match['values'] as List<dynamic>).cast<double>()),
              score: (match['score'] as num).toDouble(),
              metadata: match['metadata'] as Map<String, dynamic>? ?? {},
            ))
        .toList();
  }

  @override
  Future<bool> deleteEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    final body = {
      'ids': [id],
      'namespace': namespace ?? 'default',
    };

    await _makeRequest('POST', '/vectors/delete', body: body);
    _logger.debug('Deleted embedding $id from namespace: ${namespace ?? 'default'}');
    return true;
  }

  @override
  Future<int> deleteEmbeddingBatch(List<String> ids, {String? namespace}) async {
    await _ensureInitialized();
    
    // Split into batches of 1000 IDs (Pinecone limit)
    const batchSize = 1000;
    for (int i = 0; i < ids.length; i += batchSize) {
      final batch = ids.skip(i).take(batchSize).toList();
      final body = {
        'ids': batch,
        'namespace': namespace ?? 'default',
      };
      await _makeRequest('POST', '/vectors/delete', body: body);
    }
    
    _logger.debug('Deleted ${ids.length} embeddings from namespace: ${namespace ?? 'default'}');
    return ids.length;
  }

  @override
  Future<bool> exists(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    // Pinecone doesn't have a direct exists API, so we use fetch
    final body = {
      'ids': [id],
      'namespace': namespace ?? 'default',
    };

    try {
      final response = await _makeRequest('GET', '/vectors/fetch', body: body);
      final vectors = response['vectors'] as Map<String, dynamic>?;
      return vectors != null && vectors.containsKey(id);
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Embedding?> getEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    final body = {
      'ids': [id],
      'namespace': namespace ?? 'default',
    };

    try {
      final response = await _makeRequest('GET', '/vectors/fetch', body: body);
      final vectors = response['vectors'] as Map<String, dynamic>?;
      if (vectors != null && vectors.containsKey(id)) {
        final vector = vectors[id]['values'] as List<dynamic>;
        return Embedding(vector.cast<double>());
      }
    } catch (e) {
      _logger.debug('Failed to get embedding $id: $e');
    }
    return null;
  }

  @override
  Future<void> createNamespace(String namespace, {Map<String, dynamic> options = const {}}) async {
    // Pinecone creates namespaces automatically on first use
    _logger.debug('Namespace $namespace will be created on first use');
  }

  @override
  Future<bool> deleteNamespace(String namespace) async {
    await _ensureInitialized();

    final body = {
      'deleteAll': true,
      'namespace': namespace,
    };

    await _makeRequest('POST', '/vectors/delete', body: body);
    _logger.debug('Deleted all vectors from namespace: $namespace');
    return true;
  }

  @override
  Future<List<String>> listNamespaces() async {
    await _ensureInitialized();
    
    final response = await _makeRequest('GET', '/describe_index_stats');
    final namespaces = response['namespaces'] as Map<String, dynamic>? ?? {};
    return namespaces.keys.toList();
  }

  @override
  Future<void> upsertDocument(Document document, {String? namespace}) async {
    if (document.embedding == null) {
      throw ArgumentError('Document must have embedding');
    }
    await storeEmbedding(
      document.id,
      Embedding(document.embedding!),
      metadata: {
        ...document.metadata,
        'content': document.content,
      },
      namespace: namespace,
    );
  }

  @override
  Future<void> upsertDocumentBatch(List<Document> documents, {String? namespace}) async {
    final embeddings = <String, Embedding>{};
    final metadata = <String, Map<String, dynamic>>{};
    
    for (final doc in documents) {
      if (doc.embedding == null) {
        throw ArgumentError('All documents must have embeddings');
      }
      embeddings[doc.id] = Embedding(doc.embedding!);
      metadata[doc.id] = {
        ...doc.metadata,
        'content': doc.content,
      };
    }
    
    await storeEmbeddingBatch(embeddings, metadata: metadata, namespace: namespace);
  }

  @override
  Future<Document?> getDocument(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    final body = {
      'ids': [id],
      'namespace': namespace ?? 'default',
    };

    try {
      final response = await _makeRequest('GET', '/vectors/fetch', body: body);
      final vectors = response['vectors'] as Map<String, dynamic>?;
      if (vectors != null && vectors.containsKey(id)) {
        final vectorData = vectors[id];
        final vector = vectorData['values'] as List<dynamic>;
        final metadata = vectorData['metadata'] as Map<String, dynamic>? ?? {};
        
        return Document(
          id: id,
          title: metadata['title'] ?? '',
          content: metadata['content'] ?? '',
          metadata: Map<String, dynamic>.from(metadata)..remove('content')..remove('title'),
          embedding: vector.cast<double>(),
        );
      }
    } catch (e) {
      _logger.debug('Failed to get document $id: $e');
    }
    return null;
  }

  @override
  Future<List<ScoredDocument>> findSimilarDocuments(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    final results = await findSimilar(
      queryEmbedding,
      limit: limit,
      scoreThreshold: scoreThreshold,
      namespace: namespace,
      filters: filters,
    );
    
    final documents = <ScoredDocument>[];
    for (final result in results) {
      final doc = Document(
        id: result.id,
        title: result.metadata['title'] ?? '',
        content: result.metadata['content'] ?? '',
        metadata: Map<String, dynamic>.from(result.metadata)..remove('content')..remove('title'),
        embedding: result.embedding.vector,
      );
      documents.add(ScoredDocument(doc, result.score));
    }
    return documents;
  }

  Future<void> _upsertBatch(String namespace, List<VectorDocument> documents) async {
    final vectors = documents.map((doc) => {
      'id': doc.id,
      'values': doc.vector,
      'metadata': doc.metadata,
    }).toList();

    final body = {
      'vectors': vectors,
      'namespace': namespace,
    };

    await _makeRequest('POST', '/vectors/upsert', body: body);
  }

  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse('$_baseUrl$path');
    http.Response response;
    
    final headers = {
      'Api-Key': apiKey,
      'Content-Type': 'application/json',
    };

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient.get(url, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(url, headers: headers);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isNotEmpty) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {};
    } else {
      throw Exception('Pinecone API error: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    _logger.debug('Pinecone vector store closed');
  }
}

/// Weaviate vector store implementation
class RealWeaviateVectorStore implements VectorStore {
  final String url;
  final String? apiKey;
  final String className;
  final int dimension;
  final http.Client _httpClient;
  
  bool _initialized = false;

  RealWeaviateVectorStore({
    required this.url,
    this.apiKey,
    required this.className,
    required this.dimension,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Test connection by checking if class exists
      await _getClass(className);
      _initialized = true;
      _logger.info('Weaviate vector store initialized: $className');
    } catch (e) {
      // Try to create the class if it doesn't exist
      try {
        await _createClass();
        _initialized = true;
        _logger.info('Weaviate class created and initialized: $className');
      } catch (createError) {
        throw Exception('Failed to initialize Weaviate vector store: $createError');
      }
    }
  }

  Future<void> _createClass() async {
    final classDefinition = {
      'class': className,
      'vectorizer': 'none', // We'll provide vectors directly
      'properties': [
        {
          'name': 'content',
          'dataType': ['text'],
        },
        {
          'name': 'metadata',
          'dataType': ['object'],
        },
        {
          'name': 'namespace',
          'dataType': ['text'],
        },
      ],
    };

    await _makeRequest('POST', '/v1/schema', body: classDefinition);
  }

  Future<Map<String, dynamic>> _getClass(String name) async {
    return await _makeRequest('GET', '/v1/schema/$name');
  }

  @override
  Future<void> storeEmbedding(String id, Embedding embedding, {
    Map<String, dynamic> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();

    final object = {
      'class': className,
      'id': id,
      'vector': embedding.vector,
      'properties': {
        'content': metadata['content'] ?? '',
        'metadata': metadata,
        'namespace': namespace ?? 'default',
      },
    };

    await _makeRequest('POST', '/v1/objects', body: object);
    _logger.debug('Stored embedding $id in namespace: ${namespace ?? 'default'}');
  }

  @override
  Future<void> storeEmbeddingBatch(Map<String, Embedding> embeddings, {
    Map<String, Map<String, dynamic>> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();

    final objects = embeddings.entries.map((entry) => {
      'class': className,
      'id': entry.key,
      'vector': entry.value.vector,
      'properties': {
        'content': metadata[entry.key]?['content'] ?? '',
        'metadata': metadata[entry.key] ?? {},
        'namespace': namespace ?? 'default',
      },
    }).toList();

    // Batch insert
    final body = {
      'objects': objects,
    };

    await _makeRequest('POST', '/v1/batch/objects', body: body);
    _logger.debug('Stored ${embeddings.length} embeddings in namespace: ${namespace ?? 'default'}');
  }

  @override
  Future<List<ScoredEmbedding>> findSimilar(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    await _ensureInitialized();

    // Build GraphQL query for vector search
    final whereClause = <String, dynamic>{
      'path': ['namespace'],
      'operator': 'Equal',
      'valueText': namespace ?? 'default',
    };

    // Add additional filters if provided
    if (filters.isNotEmpty) {
      final additionalFilters = filters.entries.map((entry) => {
        'path': ['metadata', entry.key],
        'operator': 'Equal',
        'valueText': entry.value.toString(),
      }).toList();

      whereClause['operator'] = 'And';
      whereClause['operands'] = [whereClause, ...additionalFilters];
    }

    final query = {
      'query': '''
        {
          Get {
            $className(
              nearVector: {
                vector: ${jsonEncode(queryEmbedding.vector)}
              }
              limit: $limit
              where: ${jsonEncode(whereClause)}
            ) {
              _additional {
                id
                certainty
                vector
              }
              content
              metadata
              namespace
            }
          }
        }
      ''',
    };

    final response = await _makeRequest('POST', '/v1/graphql', body: query);
    final data = response['data']['Get'][className] as List<dynamic>;

    return data
        .where((item) {
          final certainty = (item['_additional']['certainty'] as num).toDouble();
          return scoreThreshold == null || certainty >= scoreThreshold;
        })
        .map((item) {
          final additional = item['_additional'] as Map<String, dynamic>;
          final vector = (additional['vector'] as List<dynamic>).cast<double>();
          return ScoredEmbedding(
            id: additional['id'] as String,
            embedding: Embedding(vector),
            score: (additional['certainty'] as num).toDouble(),
            metadata: item['metadata'] as Map<String, dynamic>? ?? {},
          );
        })
        .toList();
  }

  @override
  Future<bool> deleteEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();
    await _makeRequest('DELETE', '/v1/objects/$className/$id');
    _logger.debug('Deleted embedding $id');
    return true;
  }

  @override
  Future<int> deleteEmbeddingBatch(List<String> ids, {String? namespace}) async {
    await _ensureInitialized();
    
    for (final id in ids) {
      await _makeRequest('DELETE', '/v1/objects/$className/$id');
    }
    
    _logger.debug('Deleted ${ids.length} embeddings');
    return ids.length;
  }

  @override
  Future<bool> exists(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    try {
      await _makeRequest('GET', '/v1/objects/$className/$id');
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Embedding?> getEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    try {
      final response = await _makeRequest('GET', '/v1/objects/$className/$id?include=vector');
      final vector = response['vector'] as List<dynamic>?;
      if (vector != null) {
        return Embedding(vector.cast<double>());
      }
    } catch (e) {
      _logger.debug('Failed to get embedding $id: $e');
    }
    return null;
  }

  @override
  Future<void> createNamespace(String namespace, {Map<String, dynamic> options = const {}}) async {
    // Weaviate doesn't have native namespaces, we use a property
    _logger.debug('Namespace $namespace will be created as needed');
  }

  @override
  Future<bool> deleteNamespace(String namespace) async {
    await _ensureInitialized();

    // Delete by namespace using GraphQL
    final query = {
      'query': '''
        mutation {
          BatchDelete(
            className: "$className"
            where: {
              path: ["namespace"]
              operator: Equal
              valueText: "$namespace"
            }
          ) {
            successful
            failed
            objectsDeleted
          }
        }
      ''',
    };

    await _makeRequest('POST', '/v1/graphql', body: query);
    _logger.debug('Deleted all documents from namespace: $namespace');
    return true;
  }

  @override
  Future<List<String>> listNamespaces() async {
    await _ensureInitialized();
    
    // Get unique namespaces using GraphQL aggregate
    final query = {
      'query': '''
        {
          Aggregate {
            $className {
              namespace {
                topOccurrences {
                  value
                  occurs
                }
              }
            }
          }
        }
      ''',
    };

    final response = await _makeRequest('POST', '/v1/graphql', body: query);
    final data = response['data']['Aggregate'][className];
    if (data == null || data.isEmpty) return [];
    
    final namespaceData = data[0]['namespace'] as Map<String, dynamic>?;
    if (namespaceData == null) return [];
    
    final topOccurrences = namespaceData['topOccurrences'] as List<dynamic>? ?? [];
    return topOccurrences.map((item) => item['value'] as String).toList();
  }

  @override
  Future<void> upsertDocument(Document document, {String? namespace}) async {
    if (document.embedding == null) {
      throw ArgumentError('Document must have embedding');
    }
    await storeEmbedding(
      document.id,
      Embedding(document.embedding!),
      metadata: {
        ...document.metadata,
        'content': document.content,
      },
      namespace: namespace,
    );
  }

  @override
  Future<void> upsertDocumentBatch(List<Document> documents, {String? namespace}) async {
    final embeddings = <String, Embedding>{};
    final metadata = <String, Map<String, dynamic>>{};
    
    for (final doc in documents) {
      if (doc.embedding == null) {
        throw ArgumentError('All documents must have embeddings');
      }
      embeddings[doc.id] = Embedding(doc.embedding!);
      metadata[doc.id] = {
        ...doc.metadata,
        'content': doc.content,
      };
    }
    
    await storeEmbeddingBatch(embeddings, metadata: metadata, namespace: namespace);
  }

  @override
  Future<Document?> getDocument(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    try {
      final response = await _makeRequest('GET', '/v1/objects/$className/$id?include=vector');
      final properties = response['properties'] as Map<String, dynamic>;
      final vector = response['vector'] as List<dynamic>?;
      
      if (vector != null) {
        return Document(
          id: id,
          title: properties['title'] ?? '',
          content: properties['content'] ?? '',
          metadata: properties['metadata'] as Map<String, dynamic>? ?? {},
          embedding: vector.cast<double>(),
        );
      }
    } catch (e) {
      _logger.debug('Failed to get document $id: $e');
    }
    return null;
  }

  @override
  Future<List<ScoredDocument>> findSimilarDocuments(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    final results = await findSimilar(
      queryEmbedding,
      limit: limit,
      scoreThreshold: scoreThreshold,
      namespace: namespace,
      filters: filters,
    );
    
    final documents = <ScoredDocument>[];
    for (final result in results) {
      final doc = await getDocument(result.id, namespace: namespace);
      if (doc != null) {
        documents.add(ScoredDocument(doc, result.score));
      }
    }
    return documents;
  }

  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final requestUrl = Uri.parse('$url$path');
    http.Response response;
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (apiKey != null) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient.get(requestUrl, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          requestUrl,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(requestUrl, headers: headers);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Weaviate API error: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    _logger.debug('Weaviate vector store closed');
  }
}

/// Qdrant vector store implementation
class RealQdrantVectorStore implements VectorStore {
  final String url;
  final String? apiKey;
  final String collectionName;
  final int dimension;
  final http.Client _httpClient;
  
  bool _initialized = false;

  RealQdrantVectorStore({
    required this.url,
    this.apiKey,
    required this.collectionName,
    required this.dimension,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Check if collection exists
      await _getCollection(collectionName);
      _initialized = true;
      _logger.info('Qdrant vector store initialized: $collectionName');
    } catch (e) {
      // Try to create the collection if it doesn't exist
      try {
        await _createCollection();
        _initialized = true;
        _logger.info('Qdrant collection created and initialized: $collectionName');
      } catch (createError) {
        throw Exception('Failed to initialize Qdrant vector store: $createError');
      }
    }
  }

  Future<void> _createCollection() async {
    final collectionConfig = {
      'vectors': {
        'size': dimension,
        'distance': 'Cosine',
      },
    };

    await _makeRequest('PUT', '/collections/$collectionName', body: collectionConfig);
  }

  Future<Map<String, dynamic>> _getCollection(String name) async {
    return await _makeRequest('GET', '/collections/$name');
  }

  @override
  Future<void> storeEmbedding(String id, Embedding embedding, {
    Map<String, dynamic> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();

    final point = {
      'id': id,
      'vector': embedding.vector,
      'payload': {
        ...metadata,
        'namespace': namespace ?? 'default',
      },
    };

    final body = {
      'points': [point],
    };

    await _makeRequest('PUT', '/collections/$collectionName/points', body: body);
    _logger.debug('Stored embedding $id in namespace: ${namespace ?? 'default'}');
  }

  @override
  Future<void> storeEmbeddingBatch(Map<String, Embedding> embeddings, {
    Map<String, Map<String, dynamic>> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();

    final points = embeddings.entries.map((entry) => {
      'id': entry.key,
      'vector': entry.value.vector,
      'payload': {
        ...metadata[entry.key] ?? {},
        'namespace': namespace ?? 'default',
      },
    }).toList();

    final body = {
      'points': points,
    };

    await _makeRequest('PUT', '/collections/$collectionName/points', body: body);
    _logger.debug('Stored ${embeddings.length} embeddings in namespace: ${namespace ?? 'default'}');
  }

  @override
  Future<List<ScoredEmbedding>> findSimilar(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    await _ensureInitialized();

    // Build filter for namespace
    final mustFilters = [
      {
        'key': 'namespace',
        'match': {'value': namespace ?? 'default'},
      }
    ];

    // Add additional filters if provided
    if (filters.isNotEmpty) {
      for (final entry in filters.entries) {
        mustFilters.add({
          'key': entry.key,
          'match': {'value': entry.value},
        });
      }
    }

    final searchBody = {
      'vector': queryEmbedding.vector,
      'limit': limit,
      'with_payload': true,
      'with_vector': true,
      'filter': {
        'must': mustFilters,
      },
    };

    if (scoreThreshold != null) {
      searchBody['score_threshold'] = scoreThreshold;
    }

    final response = await _makeRequest('POST', '/collections/$collectionName/points/search', body: searchBody);
    final result = response['result'] as List<dynamic>;

    return result.map((item) => ScoredEmbedding(
      id: item['id'].toString(),
      embedding: Embedding((item['vector'] as List<dynamic>).cast<double>()),
      score: (item['score'] as num).toDouble(),
      metadata: item['payload'] as Map<String, dynamic>? ?? {},
    )).toList();
  }

  @override
  Future<bool> deleteEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();

    final body = {
      'points': [id],
    };

    await _makeRequest('POST', '/collections/$collectionName/points/delete', body: body);
    _logger.debug('Deleted embedding $id');
    return true;
  }

  @override
  Future<int> deleteEmbeddingBatch(List<String> ids, {String? namespace}) async {
    await _ensureInitialized();

    final body = {
      'points': ids,
    };

    await _makeRequest('POST', '/collections/$collectionName/points/delete', body: body);
    _logger.debug('Deleted ${ids.length} embeddings');
    return ids.length;
  }

  @override
  Future<bool> exists(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    try {
      final response = await _makeRequest('GET', '/collections/$collectionName/points/$id');
      return response['result'] != null;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Embedding?> getEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    try {
      final response = await _makeRequest('GET', '/collections/$collectionName/points/$id');
      final result = response['result'];
      if (result != null && result['vector'] != null) {
        return Embedding((result['vector'] as List<dynamic>).cast<double>());
      }
    } catch (e) {
      _logger.debug('Failed to get embedding $id: $e');
    }
    return null;
  }

  @override
  Future<void> createNamespace(String namespace, {Map<String, dynamic> options = const {}}) async {
    // Qdrant doesn't have native namespaces, we use payload field
    _logger.debug('Namespace $namespace will be created as needed');
  }

  @override
  Future<bool> deleteNamespace(String namespace) async {
    await _ensureInitialized();

    final body = {
      'filter': {
        'must': [
          {
            'key': 'namespace',
            'match': {'value': namespace},
          }
        ],
      },
    };

    await _makeRequest('POST', '/collections/$collectionName/points/delete', body: body);
    _logger.debug('Deleted all embeddings from namespace: $namespace');
    return true;
  }

  @override
  Future<List<String>> listNamespaces() async {
    await _ensureInitialized();
    
    // Get unique namespaces by scrolling through points
    final namespaces = <String>{};
    String? nextPageOffset;
    
    do {
      final body = <String, dynamic>{
        'limit': 100,
        'with_payload': true,
      };
      
      if (nextPageOffset != null) {
        body['offset'] = nextPageOffset;
      }
      
      final response = await _makeRequest('POST', '/collections/$collectionName/points/scroll', body: body);
      final points = response['result']['points'] as List<dynamic>;
      
      for (final point in points) {
        final payload = point['payload'] as Map<String, dynamic>?;
        if (payload != null && payload['namespace'] != null) {
          namespaces.add(payload['namespace'] as String);
        }
      }
      
      nextPageOffset = response['result']['next_page_offset'] as String?;
    } while (nextPageOffset != null);
    
    return namespaces.toList();
  }

  @override
  Future<void> upsertDocument(Document document, {String? namespace}) async {
    if (document.embedding == null) {
      throw ArgumentError('Document must have embedding');
    }
    await storeEmbedding(
      document.id,
      Embedding(document.embedding!),
      metadata: {
        ...document.metadata,
        'content': document.content,
      },
      namespace: namespace,
    );
  }

  @override
  Future<void> upsertDocumentBatch(List<Document> documents, {String? namespace}) async {
    final embeddings = <String, Embedding>{};
    final metadata = <String, Map<String, dynamic>>{};
    
    for (final doc in documents) {
      if (doc.embedding == null) {
        throw ArgumentError('All documents must have embeddings');
      }
      embeddings[doc.id] = Embedding(doc.embedding!);
      metadata[doc.id] = {
        ...doc.metadata,
        'content': doc.content,
      };
    }
    
    await storeEmbeddingBatch(embeddings, metadata: metadata, namespace: namespace);
  }

  @override
  Future<Document?> getDocument(String id, {String? namespace}) async {
    await _ensureInitialized();
    
    try {
      final response = await _makeRequest('GET', '/collections/$collectionName/points/$id');
      final result = response['result'];
      if (result != null) {
        final payload = result['payload'] as Map<String, dynamic>? ?? {};
        final vector = result['vector'] as List<dynamic>?;
        
        if (vector != null) {
          return Document(
            id: id,
            title: payload['title'] ?? '',
            content: payload['content'] ?? '',
            metadata: Map<String, dynamic>.from(payload)..remove('content')..remove('title')..remove('namespace'),
            embedding: vector.cast<double>(),
          );
        }
      }
    } catch (e) {
      _logger.debug('Failed to get document $id: $e');
    }
    return null;
  }

  @override
  Future<List<ScoredDocument>> findSimilarDocuments(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    final results = await findSimilar(
      queryEmbedding,
      limit: limit,
      scoreThreshold: scoreThreshold,
      namespace: namespace,
      filters: filters,
    );
    
    final documents = <ScoredDocument>[];
    for (final result in results) {
      final payload = result.metadata;
      final doc = Document(
        id: result.id,
        title: payload['title'] ?? '',
        content: payload['content'] ?? '',
        metadata: Map<String, dynamic>.from(payload)..remove('content')..remove('title')..remove('namespace'),
        embedding: result.embedding.vector,
      );
      documents.add(ScoredDocument(doc, result.score));
    }
    return documents;
  }

  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final requestUrl = Uri.parse('$url$path');
    http.Response response;
    
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (apiKey != null) {
      headers['Api-Key'] = apiKey!;
    }

    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient.get(requestUrl, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          requestUrl,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      case 'PUT':
        response = await _httpClient.put(
          requestUrl,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(requestUrl, headers: headers);
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Qdrant API error: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    _logger.debug('Qdrant vector store closed');
  }
}

/// High-performance in-memory vector store with persistence
class OptimizedMemoryVectorStore implements VectorStore {
  final int dimension;
  final String? persistencePath;
  final int maxVectors;
  
  final Map<String, Map<String, VectorDocument>> _data = {};
  final Map<String, List<double>> _vectors = {};
  bool _initialized = false;
  
  // Performance optimization: pre-computed norms for cosine similarity
  final Map<String, double> _vectorNorms = {};

  OptimizedMemoryVectorStore({
    required this.dimension,
    this.persistencePath,
    this.maxVectors = 100000,
  });

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Load from persistence if path is provided
    if (persistencePath != null) {
      await _loadFromFile();
    }

    _initialized = true;
    _logger.info('Optimized memory vector store initialized (max: $maxVectors vectors)');
  }

  @override
  Future<void> storeEmbedding(String id, Embedding embedding, {
    Map<String, dynamic> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();

    final ns = namespace ?? 'default';
    _data[ns] ??= {};
    
    if (embedding.vector.length != dimension) {
      throw ArgumentError('Vector dimension ${embedding.vector.length} does not match expected $dimension');
    }

    // Check capacity
    final totalVectors = _vectors.length;
    if (totalVectors >= maxVectors && !_vectors.containsKey(id)) {
      throw StateError('Maximum vector capacity ($maxVectors) reached');
    }

    final doc = VectorDocument(
      id: id,
      vector: embedding.vector,
      metadata: metadata,
    );

    _data[ns]![id] = doc;
    _vectors[id] = embedding.vector;
    
    // Pre-compute and cache vector norm for performance
    _vectorNorms[id] = _computeNorm(embedding.vector);

    // Persist if path is provided
    if (persistencePath != null) {
      await _saveToFile();
    }

    _logger.debug('Stored embedding $id in namespace: $ns');
  }

  @override
  Future<void> storeEmbeddingBatch(Map<String, Embedding> embeddings, {
    Map<String, Map<String, dynamic>> metadata = const {},
    String? namespace,
  }) async {
    await _ensureInitialized();

    final ns = namespace ?? 'default';
    _data[ns] ??= {};
    
    for (final entry in embeddings.entries) {
      final id = entry.key;
      final embedding = entry.value;
      
      if (embedding.vector.length != dimension) {
        throw ArgumentError('Vector dimension ${embedding.vector.length} does not match expected $dimension');
      }

      // Check capacity
      final totalVectors = _vectors.length;
      if (totalVectors >= maxVectors && !_vectors.containsKey(id)) {
        throw StateError('Maximum vector capacity ($maxVectors) reached');
      }

      final doc = VectorDocument(
        id: id,
        vector: embedding.vector,
        metadata: metadata[id] ?? {},
      );

      _data[ns]![id] = doc;
      _vectors[id] = embedding.vector;
      _vectorNorms[id] = _computeNorm(embedding.vector);
    }

    // Persist if path is provided
    if (persistencePath != null) {
      await _saveToFile();
    }

    _logger.debug('Stored ${embeddings.length} embeddings in namespace: $ns');
  }

  @override
  Future<List<ScoredEmbedding>> findSimilar(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    await _ensureInitialized();

    final ns = namespace ?? 'default';
    final namespaceData = _data[ns];
    if (namespaceData == null || namespaceData.isEmpty) {
      return [];
    }

    if (queryEmbedding.vector.length != dimension) {
      throw ArgumentError('Query vector dimension ${queryEmbedding.vector.length} does not match expected $dimension');
    }

    final queryNorm = _computeNorm(queryEmbedding.vector);
    final results = <_ScoredResult>[];

    // Compute similarities for all vectors in namespace
    for (final entry in namespaceData.entries) {
      final docId = entry.key;
      final doc = entry.value;
      
      // Apply filter if provided
      if (filters.isNotEmpty && !_matchesFilter(doc.metadata, filters)) {
        continue;
      }

      final docVector = _vectors[docId]!;
      final docNorm = _vectorNorms[docId]!;
      
      // Cosine similarity using pre-computed norms
      final similarity = _cosineSimilarity(queryEmbedding.vector, docVector, queryNorm, docNorm);
      
      if (scoreThreshold == null || similarity >= scoreThreshold) {
        results.add(_ScoredResult(
          id: docId,
          score: similarity,
          document: doc,
        ));
      }
    }

    // Sort by score (descending) and take top K
    results.sort((a, b) => b.score.compareTo(a.score));
    final topResults = results.take(limit).toList();

    return topResults.map((result) => ScoredEmbedding(
      id: result.id,
      embedding: Embedding(result.document.vector),
      score: result.score,
      metadata: result.document.metadata,
    )).toList();
  }

  @override
  Future<bool> deleteEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();

    final ns = namespace ?? 'default';
    final namespaceData = _data[ns];
    if (namespaceData != null && namespaceData.containsKey(id)) {
      namespaceData.remove(id);
      _vectors.remove(id);
      _vectorNorms.remove(id);

      // Persist if path is provided
      if (persistencePath != null) {
        await _saveToFile();
      }

      _logger.debug('Deleted embedding $id from namespace: $ns');
      return true;
    }
    return false;
  }

  @override
  Future<int> deleteEmbeddingBatch(List<String> ids, {String? namespace}) async {
    await _ensureInitialized();

    final ns = namespace ?? 'default';
    final namespaceData = _data[ns];
    int deleted = 0;
    
    if (namespaceData != null) {
      for (final id in ids) {
        if (namespaceData.containsKey(id)) {
          namespaceData.remove(id);
          _vectors.remove(id);
          _vectorNorms.remove(id);
          deleted++;
        }
      }
    }

    // Persist if path is provided
    if (persistencePath != null) {
      await _saveToFile();
    }

    _logger.debug('Deleted $deleted embeddings from namespace: $ns');
    return deleted;
  }

  @override
  Future<bool> exists(String id, {String? namespace}) async {
    await _ensureInitialized();
    final ns = namespace ?? 'default';
    return _data[ns]?.containsKey(id) ?? false;
  }

  @override
  Future<Embedding?> getEmbedding(String id, {String? namespace}) async {
    await _ensureInitialized();
    final ns = namespace ?? 'default';
    final doc = _data[ns]?[id];
    return doc != null ? Embedding(doc.vector) : null;
  }

  @override
  Future<void> createNamespace(String namespace, {Map<String, dynamic> options = const {}}) async {
    await _ensureInitialized();
    _data[namespace] ??= {};
    _logger.debug('Created namespace: $namespace');
  }

  @override
  Future<bool> deleteNamespace(String namespace) async {
    await _ensureInitialized();
    
    final namespaceData = _data[namespace];
    if (namespaceData != null) {
      // Remove all vectors from this namespace
      for (final id in namespaceData.keys) {
        _vectors.remove(id);
        _vectorNorms.remove(id);
      }
      _data.remove(namespace);

      // Persist if path is provided
      if (persistencePath != null) {
        await _saveToFile();
      }

      _logger.debug('Deleted namespace: $namespace');
      return true;
    }
    return false;
  }

  @override
  Future<List<String>> listNamespaces() async {
    await _ensureInitialized();
    return _data.keys.toList();
  }

  @override
  Future<void> upsertDocument(Document document, {String? namespace}) async {
    if (document.embedding == null) {
      throw ArgumentError('Document must have embedding');
    }
    await storeEmbedding(
      document.id,
      Embedding(document.embedding!),
      metadata: {
        ...document.metadata,
        'content': document.content,
      },
      namespace: namespace,
    );
  }

  @override
  Future<void> upsertDocumentBatch(List<Document> documents, {String? namespace}) async {
    final embeddings = <String, Embedding>{};
    final metadata = <String, Map<String, dynamic>>{};
    
    for (final doc in documents) {
      if (doc.embedding == null) {
        throw ArgumentError('All documents must have embeddings');
      }
      embeddings[doc.id] = Embedding(doc.embedding!);
      metadata[doc.id] = {
        ...doc.metadata,
        'content': doc.content,
      };
    }
    
    await storeEmbeddingBatch(embeddings, metadata: metadata, namespace: namespace);
  }

  @override
  Future<Document?> getDocument(String id, {String? namespace}) async {
    await _ensureInitialized();
    final ns = namespace ?? 'default';
    final doc = _data[ns]?[id];
    if (doc != null) {
      return Document(
        id: id,
        title: doc.metadata['title'] ?? '',
        content: doc.metadata['content'] ?? '',
        metadata: Map<String, dynamic>.from(doc.metadata)..remove('content')..remove('title'),
        embedding: doc.vector,
      );
    }
    return null;
  }

  @override
  Future<List<ScoredDocument>> findSimilarDocuments(
    Embedding queryEmbedding, {
    int limit = 5,
    double? scoreThreshold,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    final results = await findSimilar(
      queryEmbedding,
      limit: limit,
      scoreThreshold: scoreThreshold,
      namespace: namespace,
      filters: filters,
    );
    
    final documents = <ScoredDocument>[];
    for (final result in results) {
      final doc = await getDocument(result.id, namespace: namespace);
      if (doc != null) {
        documents.add(ScoredDocument(doc, result.score));
      }
    }
    return documents;
  }

  double _computeNorm(List<double> vector) {
    double norm = 0.0;
    for (final value in vector) {
      norm += value * value;
    }
    return sqrt(norm);
  }

  double _cosineSimilarity(List<double> a, List<double> b, double normA, double normB) {
    if (normA == 0.0 || normB == 0.0) return 0.0;
    
    double dotProduct = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }
    
    return dotProduct / (normA * normB);
  }

  bool _matchesFilter(Map<String, dynamic> metadata, Map<String, dynamic> filter) {
    for (final entry in filter.entries) {
      final key = entry.key;
      final expectedValue = entry.value;
      final actualValue = metadata[key];
      
      if (actualValue != expectedValue) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadFromFile() async {
    try {
      final file = File(persistencePath!);
      if (!await file.exists()) return;

      final contents = await file.readAsString();
      final data = jsonDecode(contents) as Map<String, dynamic>;
      
      // Restore data structures
      final namespacesData = data['namespaces'] as Map<String, dynamic>;
      for (final entry in namespacesData.entries) {
        final namespace = entry.key;
        final documentsData = entry.value as Map<String, dynamic>;
        
        _data[namespace] = {};
        for (final docEntry in documentsData.entries) {
          final docId = docEntry.key;
          final docData = docEntry.value as Map<String, dynamic>;
          
          final doc = VectorDocument(
            id: docId,
            vector: (docData['vector'] as List<dynamic>).cast<double>(),
            metadata: docData['metadata'] as Map<String, dynamic>,
          );
          
          _data[namespace]![docId] = doc;
          _vectors[docId] = doc.vector;
          _vectorNorms[docId] = _computeNorm(doc.vector);
        }
      }
      
      _logger.debug('Loaded ${_vectors.length} vectors from persistence file');
    } catch (e) {
      _logger.warning('Failed to load from persistence file: $e');
    }
  }

  Future<void> _saveToFile() async {
    try {
      final file = File(persistencePath!);
      await file.parent.create(recursive: true);
      
      final data = <String, dynamic>{
        'namespaces': {},
        'dimension': dimension,
        'version': '1.0',
      };
      
      for (final entry in _data.entries) {
        final namespace = entry.key;
        final documents = entry.value;
        
        data['namespaces'][namespace] = {};
        for (final docEntry in documents.entries) {
          final docId = docEntry.key;
          final doc = docEntry.value;
          
          data['namespaces'][namespace][docId] = {
            'vector': doc.vector,
            'metadata': doc.metadata,
          };
        }
      }
      
      await file.writeAsString(jsonEncode(data));
      _logger.debug('Saved ${_vectors.length} vectors to persistence file');
    } catch (e) {
      _logger.warning('Failed to save to persistence file: $e');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  @override
  Future<void> close() async {
    if (persistencePath != null) {
      await _saveToFile();
    }
    _logger.debug('Optimized memory vector store closed');
  }

  /// Get memory usage statistics
  Map<String, dynamic> getMemoryStats() {
    final vectorMemory = _vectors.length * dimension * 8; // 8 bytes per double
    final metadataMemory = _data.values
        .expand((ns) => ns.values)
        .map((doc) => jsonEncode(doc.metadata).length)
        .fold(0, (sum, length) => sum + length);
    
    return {
      'totalVectors': _vectors.length,
      'vectorMemoryBytes': vectorMemory,
      'metadataMemoryBytes': metadataMemory,
      'totalMemoryBytes': vectorMemory + metadataMemory,
      'maxCapacity': maxVectors,
      'utilizationPercent': (_vectors.length / maxVectors * 100).toStringAsFixed(1),
    };
  }
}

class _ScoredResult {
  final String id;
  final double score;
  final VectorDocument document;

  _ScoredResult({
    required this.id,
    required this.score,
    required this.document,
  });
}