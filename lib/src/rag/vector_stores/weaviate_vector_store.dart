import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../vector_store.dart';
import '../embeddings.dart';
import '../document_store.dart';
import '../../utils/logger.dart';

/// Weaviate vector store implementation
class WeaviateVectorStore implements VectorStore {
  final Logger _logger = Logger('mcp_llm.weaviate_vector_store');
  final String _apiKey;
  final String _baseUrl;
  final String? _defaultClassName;
  final int _dimension; // Used in createNamespace method
  final http.Client _httpClient = http.Client();
  final Map<String, dynamic> _options; // Used for additional configuration options

  bool _initialized = false;

  /// Create a new Weaviate vector store
  WeaviateVectorStore({
    required String apiKey,
    required String baseUrl,
    String? defaultClassName,
    int dimension = 1536,
    Map<String, dynamic> options = const {},
  }) : _apiKey = apiKey,
        _baseUrl = baseUrl,
        _defaultClassName = defaultClassName,
        _dimension = dimension,
        _options = options;

  @override
  Future<void> initialize() async {
    try {
      _logger.info('Initializing Weaviate vector store');

      // Check connection by making a simple schema request
      await _makeRequest(
        method: 'GET',
        url: '$_baseUrl/v1/schema',
      );

      _initialized = true;
      _logger.info('Weaviate vector store initialized successfully');
    } catch (e) {
      _logger.error('Failed to initialize Weaviate vector store: $e');
      throw Exception('Failed to initialize Weaviate vector store: $e');
    }
  }

  /// Check if store is initialized
  void _checkInitialized() {
    if (!_initialized) {
      throw StateError('Weaviate vector store is not initialized');
    }
  }

  @override
  Future<void> storeEmbedding(String id, Embedding embedding, {
    Map<String, dynamic> metadata = const {},
    String? namespace,
  }) async {
    _checkInitialized();

    final className = namespace ?? _defaultClassName;
    if (className == null) {
      throw ArgumentError('No class name specified and no default class name configured');
    }

    try {
      final properties = Map<String, dynamic>.from(metadata);

      final body = {
        'id': id,
        'class': className,
        'properties': properties,
        'vector': embedding.vector,
      };

      await _makeRequest(
        method: 'POST',
        url: '$_baseUrl/v1/objects',
        body: body,
      );

      _logger.debug('Stored embedding with ID: $id in class: $className');
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

    final className = namespace ?? _defaultClassName;
    if (className == null) {
      throw ArgumentError('No class name specified and no default class name configured');
    }

    try {
      final objects = embeddings.entries.map((entry) {
        final id = entry.key;
        final embedding = entry.value;
        final properties = metadata.containsKey(id) ? metadata[id] : <String, dynamic>{};

        return {
          'id': id,
          'class': className,
          'properties': properties,
          'vector': embedding.vector,
        };
      }).toList();

      final body = {
        'objects': objects,
      };

      await _makeRequest(
        method: 'POST',
        url: '$_baseUrl/v1/batch/objects',
        body: body,
      );

      _logger.debug('Stored ${embeddings.length} embeddings in batch in class: $className');
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

    final className = namespace ?? _defaultClassName;
    if (className == null) {
      throw ArgumentError('No class name specified and no default class name configured');
    }

    try {
      // Build GraphQL query for vector search
      final nearVector = {
        'vector': queryEmbedding.vector,
        'certainty': scoreThreshold ?? 0.7,
      };

      // Convert filter to Weaviate where filter if provided
      Map<String, dynamic>? whereFilter;
      if (filters.isNotEmpty) {
        whereFilter = _buildWhereFilter(filters);
      }

      // Get property selector
      final propertySelector = await _buildPropertySelector(className);

      final graphQlQuery = '''
      {
        Get {
          $className(
            nearVector: ${jsonEncode(nearVector)}
            ${whereFilter != null ? ', where: ${jsonEncode(whereFilter)}' : ''}
            limit: $limit
          ) {
            _additional {
              id
              certainty
              vector
            }
            $propertySelector
          }
        }
      }
      ''';

      final body = {
        'query': graphQlQuery,
      };

      final result = await _makeRequest(
        method: 'POST',
        url: '$_baseUrl/v1/graphql',
        body: body,
      );

      if (result != null) {
        final data = result['data'] as Map<String, dynamic>;
        final getResults = data['Get'] as Map<String, dynamic>;
        final results = getResults[className] as List<dynamic>;

        final scoredEmbeddings = results.map((result) {
          final additional = result['_additional'] as Map<String, dynamic>;
          final id = additional['id'] as String;
          final certainty = additional['certainty'] as double;
          final vector = (additional['vector'] as List<dynamic>).cast<double>();

          // Convert properties to metadata
          final metadata = Map<String, dynamic>.from(result);
          metadata.remove('_additional');

          return ScoredEmbedding(
            id: id,
            embedding: Embedding(vector),
            score: certainty,
            metadata: metadata,
          );
        }).toList();

        _logger.debug('Found ${scoredEmbeddings.length} similar embeddings in class: $className');
        return scoredEmbeddings;
      } else {
        throw Exception('Failed to find similar embeddings');
      }
    } catch (e) {
      _logger.error('Failed to find similar embeddings: $e');
      throw Exception('Failed to find similar embeddings: $e');
    }
  }

  @override
  Future<bool> deleteEmbedding(String id, {String? namespace}) async {
    _checkInitialized();

    try {
      await _makeRequest(
        method: 'DELETE',
        url: '$_baseUrl/v1/objects/$id',
      );
      _logger.debug('Deleted embedding with ID: $id');
      return true;
    } catch (e) {
      _logger.error('Failed to delete embedding: $e');
      return false;
    }
  }

  @override
  Future<int> deleteEmbeddingBatch(List<String> ids, {String? namespace}) async {
    _checkInitialized();

    if (ids.isEmpty) {
      return 0;
    }

    int deleteCount = 0;

    // Weaviate doesn't have a true batch delete, so do it one by one
    for (final id in ids) {
      final success = await deleteEmbedding(id, namespace: namespace);
      if (success) {
        deleteCount++;
      }
    }

    _logger.debug('Deleted $deleteCount embeddings in batch');
    return deleteCount;
  }

  @override
  Future<bool> exists(String id, {String? namespace}) async {
    _checkInitialized();

    try {
      await _makeRequest(
        method: 'HEAD',
        url: '$_baseUrl/v1/objects/$id',
      );
      return true;
    } catch (e) {
      _logger.error('Failed to check if embedding exists: $e');
      return false;
    }
  }

  @override
  Future<Embedding?> getEmbedding(String id, {String? namespace}) async {
    _checkInitialized();

    try {
      final result = await _makeRequest(
        method: 'GET',
        url: '$_baseUrl/v1/objects/$id?include=vector',
      );

      if (result != null) {
        final vector = (result['vector'] as List<dynamic>).cast<double>();
        return Embedding(vector);
      } else {
        return null;
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
      // Create class definition
      final classDefinition = {
        'class': namespace,
        'description': options['description'] ?? 'Class for storing document embeddings',
        'vectorizer': 'none', // We'll provide vectors explicitly
        'vectorIndexType': options['vectorIndexType'] ?? 'hnsw',
        'vectorIndexConfig': options['vectorIndexConfig'] ?? {
          'skip': false,
          'ef': 100,
          'efConstruction': 128,
          'maxConnections': 64,
          'vectorCacheMaxObjects': _options['vectorCacheMaxObjects'] ?? 500000,
          'dimension': _dimension, // Using the _dimension field here
        },
        'properties': [
          {
            'name': 'title',
            'dataType': ['text'],
            'description': 'Document title',
          },
          {
            'name': 'content',
            'dataType': ['text'],
            'description': 'Document content',
          },
          {
            'name': 'updated_at',
            'dataType': ['date'],
            'description': 'Last update timestamp',
          },
        ],
      };

      // Add any additional properties from options
      final additionalProperties = options['properties'] as List<dynamic>?;
      if (additionalProperties != null) {
        (classDefinition['properties'] as List).addAll(additionalProperties);
      }

      await _makeRequest(
        method: 'POST',
        url: '$_baseUrl/v1/schema',
        body: classDefinition,
      );

      _logger.info('Created namespace (class): $namespace');
    } catch (e) {
      _logger.error('Failed to create namespace: $e');
      throw Exception('Failed to create namespace: $e');
    }
  }

  @override
  Future<bool> deleteNamespace(String namespace) async {
    _checkInitialized();

    try {
      await _makeRequest(
        method: 'DELETE',
        url: '$_baseUrl/v1/schema/${Uri.encodeComponent(namespace)}',
      );
      _logger.info('Deleted namespace (class): $namespace');
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
      final result = await _makeRequest(
        method: 'GET',
        url: '$_baseUrl/v1/schema',
      );

      if (result != null) {
        final classes = result['classes'] as List<dynamic>?;

        if (classes == null) {
          return [];
        }

        final namespaces = classes.map((cls) => cls['class'] as String).toList();

        _logger.debug('Listed ${namespaces.length} namespaces (classes)');
        return namespaces;
      } else {
        return [];
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

    final className = namespace ?? _defaultClassName;
    if (className == null) {
      throw ArgumentError('No class name specified and no default class name configured');
    }

    final embedding = Embedding(document.embedding!);

    try {
      // Build properties with document fields and metadata
      final properties = {
        'title': document.title,
        'content': document.content,
        'updated_at': document.updatedAt.toIso8601String(),
        ...document.metadata,
      };

      final body = {
        'id': document.id,
        'class': className,
        'properties': properties,
        'vector': embedding.vector,
      };

      await _makeRequest(
        method: 'POST',
        url: '$_baseUrl/v1/objects',
        body: body,
      );

      _logger.debug('Upserted document with ID: ${document.id} in class: $className');
    } catch (e) {
      _logger.error('Failed to upsert document: $e');
      throw Exception('Failed to upsert document: $e');
    }
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

    final className = namespace ?? _defaultClassName;
    if (className == null) {
      throw ArgumentError('No class name specified and no default class name configured');
    }

    try {
      final objects = validDocuments.map((doc) {
        final properties = {
          'title': doc.title,
          'content': doc.content,
          'updated_at': doc.updatedAt.toIso8601String(),
          ...doc.metadata,
        };

        return {
          'id': doc.id,
          'class': className,
          'properties': properties,
          'vector': doc.embedding,
        };
      }).toList();

      final body = {
        'objects': objects,
      };

      await _makeRequest(
        method: 'POST',
        url: '$_baseUrl/v1/batch/objects',
        body: body,
      );

      _logger.debug('Upserted ${validDocuments.length} documents in batch in class: $className');
    } catch (e) {
      _logger.error('Failed to upsert documents in batch: $e');
      throw Exception('Failed to upsert documents in batch: $e');
    }
  }

  @override
  Future<Document?> getDocument(String id, {String? namespace}) async {
    _checkInitialized();

    final className = namespace ?? _defaultClassName;
    if (className == null) {
      throw ArgumentError('No class name specified and no default class name configured');
    }

    try {
      final result = await _makeRequest(
        method: 'GET',
        url: '$_baseUrl/v1/objects/$id?include=vector&include=properties',
      );

      if (result != null) {
        // Check if the object belongs to the specified class
        final objClass = result['class'] as String?;
        if (objClass != className) {
          _logger.warning('Object found but belongs to class $objClass, not $className');
          return null;
        }

        final vector = (result['vector'] as List<dynamic>).cast<double>();
        final properties = result['properties'] as Map<String, dynamic>? ?? {};

        // Extract document fields from properties
        final title = properties['title'] as String? ?? 'Untitled';
        final content = properties['content'] as String? ?? '';
        final updatedAtStr = properties['updated_at'] as String?;

        // Create a copy of properties without document fields
        final docMetadata = Map<String, dynamic>.from(properties);
        docMetadata.remove('title');
        docMetadata.remove('content');
        docMetadata.remove('updated_at');

        return Document(
          id: id,
          title: title,
          content: content,
          embedding: vector,
          metadata: docMetadata,
          collectionId: namespace,
          updatedAt: updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now(),
        );
      } else {
        return null;
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

    final className = namespace ?? _defaultClassName;
    if (className == null) {
      throw ArgumentError('No class name specified and no default class name configured');
    }

    try {
      // Build GraphQL query for vector search
      final nearVector = {
        'vector': queryEmbedding.vector,
        'certainty': scoreThreshold ?? 0.7,
      };

      // Convert filter to Weaviate where filter if provided
      Map<String, dynamic>? whereFilter;
      if (filters.isNotEmpty) {
        whereFilter = _buildWhereFilter(filters);
      }

      // Get property selector
      final propertySelector = await _buildPropertySelector(className);

      final graphQlQuery = '''
      {
        Get {
          $className(
            nearVector: ${jsonEncode(nearVector)}
            ${whereFilter != null ? ', where: ${jsonEncode(whereFilter)}' : ''}
            limit: $limit
          ) {
            _additional {
              id
              certainty
              vector
            }
            title
            content
            updated_at
            $propertySelector
          }
        }
      }
      ''';

      final body = {
        'query': graphQlQuery,
      };

      final result = await _makeRequest(
        method: 'POST',
        url: '$_baseUrl/v1/graphql',
        body: body,
      );

      if (result != null) {
        final data = result['data'] as Map<String, dynamic>;
        final getResults = data['Get'] as Map<String, dynamic>;
        final results = getResults[className] as List<dynamic>;

        final scoredDocuments = results.map((result) {
          final additional = result['_additional'] as Map<String, dynamic>;
          final id = additional['id'] as String;
          final certainty = additional['certainty'] as double;
          final vector = (additional['vector'] as List<dynamic>).cast<double>();

          // Extract document fields
          final properties = Map<String, dynamic>.from(result);
          properties.remove('_additional');

          final title = properties['title'] as String? ?? 'Untitled';
          final content = properties['content'] as String? ?? '';
          final updatedAtStr = properties['updated_at'] as String?;

          // Create metadata
          final docMetadata = Map<String, dynamic>.from(properties);
          docMetadata.remove('title');
          docMetadata.remove('content');
          docMetadata.remove('updated_at');

          final document = Document(
            id: id,
            title: title,
            content: content,
            embedding: vector,
            metadata: docMetadata,
            collectionId: namespace,
            updatedAt: updatedAtStr != null ? DateTime.parse(updatedAtStr) : DateTime.now(),
          );

          return ScoredDocument(document, certainty);
        }).toList();

        _logger.debug('Found ${scoredDocuments.length} similar documents in class: $className');
        return scoredDocuments;
      } else {
        throw Exception('Failed to find similar documents');
      }
    } catch (e) {
      _logger.error('Failed to find similar documents: $e');
      throw Exception('Failed to find similar documents: $e');
    }
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    _logger.info('Closed Weaviate vector store connection');
  }

  // Helper to get headers
  Map<String, String> _getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    // Set API key if it's not empty
    if (_apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_apiKey';
    }
    
    return headers;
  }

  // Helper to make HTTP request
  Future<Map<String, dynamic>?> _makeRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse(url);
      http.Response response;
      
      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: _getHeaders());
          break;
        case 'POST':
          response = await _httpClient.post(
            uri,
            headers: _getHeaders(),
            body: body != null ? jsonEncode(body) : null,
          );
          break;
        case 'DELETE':
          response = await _httpClient.delete(uri, headers: _getHeaders());
          break;
        case 'HEAD':
          response = await _httpClient.head(uri, headers: _getHeaders());
          break;
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) {
          return jsonDecode(response.body) as Map<String, dynamic>?;
        }
        return null;
      } else if (response.statusCode == 404) {
        // Return null for 404s to indicate not found
        return null;
      } else {
        throw Exception('API request failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logger.error('HTTP request failed: $e');
      rethrow;
    }
  }

  // Helper to build Weaviate where filter
  Map<String, dynamic> _buildWhereFilter(Map<String, dynamic> filters) {
    final operands = <Map<String, dynamic>>[];

    filters.forEach((key, value) {
      if (value is String) {
        operands.add({
          'path': [key],
          'operator': 'Equal',
          'valueString': value,
        });
      } else if (value is num) {
        if (value is int) {
          operands.add({
            'path': [key],
            'operator': 'Equal',
            'valueInt': value,
          });
        } else {
          operands.add({
            'path': [key],
            'operator': 'Equal',
            'valueNumber': value,
          });
        }
      } else if (value is bool) {
        operands.add({
          'path': [key],
          'operator': 'Equal',
          'valueBoolean': value,
        });
      } else if (value is Map<String, dynamic>) {
        // For more complex operators
        final operator = value['operator'] as String?;
        final fieldValue = value['value'];

        if (operator != null && fieldValue != null) {
          final operatorMap = _mapOperator(operator);

          if (fieldValue is String) {
            operands.add({
              'path': [key],
              'operator': operatorMap,
              'valueString': fieldValue,
            });
          } else if (fieldValue is int) {
            operands.add({
              'path': [key],
              'operator': operatorMap,
              'valueInt': fieldValue,
            });
          } else if (fieldValue is num) {
            operands.add({
              'path': [key],
              'operator': operatorMap,
              'valueNumber': fieldValue,
            });
          } else if (fieldValue is bool) {
            operands.add({
              'path': [key],
              'operator': operatorMap,
              'valueBoolean': fieldValue,
            });
          }
        }
      }
    });

    if (operands.isEmpty) {
      return {};
    } else if (operands.length == 1) {
      return operands.first;
    } else {
      return {
        'operator': 'And',
        'operands': operands,
      };
    }
  }

  // Helper to map operator strings
  String _mapOperator(String operator) {
    switch (operator.toLowerCase()) {
      case 'eq':
      case 'equal':
        return 'Equal';
      case 'neq':
      case 'notequal':
        return 'NotEqual';
      case 'gt':
      case 'greaterthan':
        return 'GreaterThan';
      case 'gte':
      case 'greaterthanequal':
        return 'GreaterThanEqual';
      case 'lt':
      case 'lessthan':
        return 'LessThan';
      case 'lte':
      case 'lessthanequal':
        return 'LessThanEqual';
      case 'like':
        return 'Like';
      case 'contains':
        return 'ContainsAny';
      case 'containsall':
        return 'ContainsAll';
      default:
        return 'Equal';
    }
  }

  // Helper to build property selector for GraphQL queries
  Future<String> _buildPropertySelector(String className) async {
    try {
      // Try to get class schema to determine properties
      final result = await _makeRequest(
        method: 'GET',
        url: '$_baseUrl/v1/schema/${Uri.encodeComponent(className)}',
      );

      if (result != null) {
        final properties = result['properties'] as List<dynamic>?;

        if (properties != null) {
          // Extract property names, excluding special fields we already handle
          final propertyNames = properties
              .map((prop) => prop['name'] as String)
              .where((name) => !['title', 'content', 'updated_at'].contains(name))
              .toList();

          return propertyNames.join('\n');
        }
      }

      // Default return empty string if we can't get schema
      return '';
    } catch (e) {
      _logger.error('Failed to build property selector: $e');
      return '';
    }
  }
}