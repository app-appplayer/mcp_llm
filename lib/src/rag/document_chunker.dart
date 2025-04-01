import 'dart:math';

import 'document_store.dart';

class DocumentChunker {
  // Default chunking settings
  final int _defaultChunkSize;
  final int _defaultChunkOverlap;

  DocumentChunker({
    int defaultChunkSize = 1000,
    int defaultChunkOverlap = 200,
  })  : _defaultChunkSize = defaultChunkSize,
        _defaultChunkOverlap = defaultChunkOverlap;

  // Split document into chunks
  List<Document> chunkDocument(
    Document document, {
    int? chunkSize,
    int? chunkOverlap,
    bool preserveMetadata = true,
  }) {
    final size = chunkSize ?? _defaultChunkSize;
    final overlap = chunkOverlap ?? _defaultChunkOverlap;

    if (size <= 0 || overlap >= size) {
      throw ArgumentError('Invalid chunk size or overlap');
    }

    // Don't chunk short documents
    if (document.content.length <= size) {
      return [document];
    }

    // Split text into chunks
    final chunks = _chunkText(document.content, size, overlap);

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

      // Create chunk document
      return Document(
        title: '${document.title} (Chunk ${index + 1}/${chunks.length})',
        content: chunkText,
        metadata: newMetadata,
        collectionId: document.collectionId,
      );
    }).toList();
  }

  // Split text into chunks with overlap
  List<String> _chunkText(String text, int chunkSize, int overlap) {
    final List<String> chunks = [];

    // Try to split by paragraph or sentence boundaries
    List<String> segments = _splitByParagraphs(text);

    if (segments.length <= 1) {
      // If no paragraphs, split by sentences
      segments = _splitBySentences(text);
    }

    if (segments.length <= 1) {
      // If no sentences either, split by words
      segments = _splitByWords(text);
    }

    // Combine segments to create chunks
    StringBuffer currentChunk = StringBuffer();

    for (final segment in segments) {
      // Check if segment can be added to current chunk
      if (currentChunk.length + segment.length > chunkSize &&
          currentChunk.isNotEmpty) {
        // Save current chunk and start a new one
        chunks.add(currentChunk.toString());

        // Apply overlap: preserve the last part of previous chunk
        if (overlap > 0 && currentChunk.length > overlap) {
          final overlapText = currentChunk
              .toString()
              .substring(max(0, currentChunk.length - overlap));
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

    return chunks;
  }

  // Split by paragraphs
  List<String> _splitByParagraphs(String text) {
    return text
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
  }

  // Split by sentences
  List<String> _splitBySentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  // Split by words
  List<String> _splitByWords(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .toList();
  }

  // Chunk multiple documents
  List<Document> chunkDocuments(
    List<Document> documents, {
    int? chunkSize,
    int? chunkOverlap,
    bool preserveMetadata = true,
  }) {
    List<Document> allChunks = [];

    for (final document in documents) {
      final documentChunks = chunkDocument(
        document,
        chunkSize: chunkSize,
        chunkOverlap: chunkOverlap,
        preserveMetadata: preserveMetadata,
      );

      allChunks.addAll(documentChunks);
    }

    return allChunks;
  }
}
