import 'dart:math';
import 'document_store.dart';
import '../utils/logger.dart';

/// Handles splitting documents into smaller chunks with improved multilingual support
class DocumentChunker {
  // Default chunking settings
  final int _defaultChunkSize;
  final int _defaultChunkOverlap;
  final Logger _logger = Logger('mcp_llm.document_chunker');

  /// Map of language codes to their approximate characters per token ratios
  /// Used for better chunk size estimation for different languages
  static const Map<String, double> _charsPerTokenByLanguage = {
    'en': 4.0,  // English: ~4 chars per token
    'zh': 1.5,  // Chinese: ~1.5 chars per token
    'ja': 1.5,  // Japanese: ~1.5 chars per token
    'ko': 2.0,  // Korean: ~2 chars per token
    'th': 2.0,  // Thai: ~2 chars per token
    'default': 4.0, // Default assumption
  };

  DocumentChunker({
    int defaultChunkSize = 1000,
    int defaultChunkOverlap = 200,
  })  : _defaultChunkSize = defaultChunkSize,
        _defaultChunkOverlap = defaultChunkOverlap;

  /// Split document into chunks with improved multilingual support
  List<Document> chunkDocument(
      Document document, {
        int? chunkSize,
        int? chunkOverlap,
        bool preserveMetadata = true,
        String? language,
      }) {
    final size = chunkSize ?? _defaultChunkSize;
    final overlap = chunkOverlap ?? _defaultChunkOverlap;

    if (size <= 0) {
      throw ArgumentError('Chunk size must be positive');
    }

    if (overlap >= size) {
      throw ArgumentError('Overlap must be less than chunk size');
    }

    // Determine language if not provided
    final detectedLanguage = language ?? _detectLanguage(document.content);

    // Don't chunk short documents
    if (_isShortContent(document.content, size, detectedLanguage)) {
      return [document];
    }

    // Split text into chunks based on detected language
    final chunks = _chunkText(document.content, size, overlap, detectedLanguage);

    // Create documents for each chunk
    return chunks.asMap().entries.map((entry) {
      final index = entry.key;
      final chunkText = entry.value;

      // Copy metadata and add chunk information
      Map<String, dynamic> newMetadata = {};
      if (preserveMetadata) {
        newMetadata = Map<String, dynamic>.from(document.metadata);
      }

      // Add chunk information
      newMetadata['chunk_index'] = index;
      newMetadata['total_chunks'] = chunks.length;
      newMetadata['parent_document_id'] = document.id;

      // Store detected language
      newMetadata['language'] = detectedLanguage;

      // Create chunk document
      return Document(
        title: '${document.title} (Chunk ${index + 1}/${chunks.length})',
        content: chunkText,
        metadata: newMetadata,
        collectionId: document.collectionId,
      );
    }).toList();
  }

  /// Detect language of the text (basic implementation)
  String _detectLanguage(String text) {
    // Sample of text for language detection (use beginning for efficiency)
    final sample = text.length > 500 ? text.substring(0, 500) : text;

    // Check for Asian languages with specific character ranges
    if (_hasKoreanChars(sample)) return 'ko';
    if (_hasJapaneseChars(sample)) return 'ja';
    if (_hasChineseChars(sample)) return 'zh';
    if (_hasThaiChars(sample)) return 'th';

    // Default to English/Latin scripts
    return 'en';
  }

  // Language detection helpers
  bool _hasKoreanChars(String text) => RegExp(r'[\uAC00-\uD7AF]').hasMatch(text);
  bool _hasJapaneseChars(String text) => RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(text);
  bool _hasChineseChars(String text) => RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
  bool _hasThaiChars(String text) => RegExp(r'[\u0E00-\u0E7F]').hasMatch(text);

  /// Check if content is short enough to avoid chunking
  bool _isShortContent(String text, int size, String language) {
    // Adjust size threshold based on language
    final charsPerToken = _charsPerTokenByLanguage[language] ??
        _charsPerTokenByLanguage['default']!;

    // For languages with fewer chars per token, we can allow more characters
    final adjustedSize = (size * (4.0 / charsPerToken)).round();

    return text.length <= adjustedSize;
  }

  /// Split text into chunks with language-specific considerations
  List<String> _chunkText(String text, int chunkSize, int overlap, String language) {
    final List<String> chunks = [];

    // Adjust chunk size based on language characteristics
    final charsPerToken = _charsPerTokenByLanguage[language] ??
        _charsPerTokenByLanguage['default']!;

    // For languages with fewer chars per token, we need more characters per chunk
    final adjustedChunkSize = (chunkSize * (4.0 / charsPerToken)).round();
    final adjustedOverlap = (overlap * (4.0 / charsPerToken)).round();

    // Choose appropriate splitting strategy based on language
    List<String> segments;

    if (language == 'zh' || language == 'ja' || language == 'th') {
      // Character-based languages benefit more from character-based splitting
      segments = _splitByCharacters(text, adjustedChunkSize ~/ 10);
    } else {
      // Try to split by paragraph or sentence boundaries for other languages
      segments = _splitByParagraphs(text);

      if (segments.length <= 1) {
        // If no paragraphs, split by sentences
        segments = _splitBySentences(text);
      }

      if (segments.length <= 1) {
        // If no sentences either, split by words
        segments = _splitByWords(text);
      }
    }

    // Combine segments to create chunks
    StringBuffer currentChunk = StringBuffer();

    for (final segment in segments) {
      // Check if segment can be added to current chunk
      if (currentChunk.length + segment.length > adjustedChunkSize &&
          currentChunk.isNotEmpty) {
        // Save current chunk and start a new one
        chunks.add(currentChunk.toString());

        // Apply overlap: preserve the last part of previous chunk
        if (adjustedOverlap > 0 && currentChunk.length > adjustedOverlap) {
          final overlapText = currentChunk
              .toString()
              .substring(max(0, currentChunk.length - adjustedOverlap));
          currentChunk = StringBuffer(overlapText);
        } else {
          currentChunk = StringBuffer();
        }
      }

      // Add segment
      currentChunk.write(segment);
    }

    // Add the last chunk
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString());
    }

    _logger.debug('Split text into ${chunks.length} chunks (language: $language)');
    return chunks;
  }

  // Split by paragraphs with improved handling of line breaks
  List<String> _splitByParagraphs(String text) {
    // Handle different types of paragraph breaks
    return text
        .split(RegExp(r'\n\s*\n|\r\n\s*\r\n'))
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.endsWith('\n') ? p : '$p\n\n')
        .toList();
  }

  // Split by sentences with improved multilingual support
  List<String> _splitBySentences(String text) {
    // Pattern matches common sentence endings in multiple languages
    return text
        .split(RegExp(r'(?<=[.!?。？！…\:\;\)\]\}])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.endsWith(' ') ? s : '$s ')
        .toList();
  }

  // Split by words
  List<String> _splitByWords(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .map((w) => '$w ')
        .toList();
  }

  // Split by characters (useful for languages like Chinese/Japanese)
  List<String> _splitByCharacters(String text, int charsPerSegment) {
    final segments = <String>[];
    for (var i = 0; i < text.length; i += charsPerSegment) {
      final end = min(i + charsPerSegment, text.length);
      segments.add(text.substring(i, end));
    }
    return segments;
  }

  /// Chunk multiple documents
  List<Document> chunkDocuments(
      List<Document> documents, {
        int? chunkSize,
        int? chunkOverlap,
        bool preserveMetadata = true,
        Map<String, String>? languageOverrides,
      }) {
    List<Document> allChunks = [];

    for (final document in documents) {
      try {
        // Check if language override exists for this document
        String? languageOverride;
        if (languageOverrides != null && languageOverrides.containsKey(document.id)) {
          languageOverride = languageOverrides[document.id];
        }

        final documentChunks = chunkDocument(
          document,
          chunkSize: chunkSize,
          chunkOverlap: chunkOverlap,
          preserveMetadata: preserveMetadata,
          language: languageOverride,
        );

        allChunks.addAll(documentChunks);
      } catch (e) {
        _logger.error('Error chunking document ${document.id}: $e');
        // Add original document to avoid data loss
        allChunks.add(document);
      }
    }

    return allChunks;
  }
}