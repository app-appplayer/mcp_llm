/// Image content as the providers read it, whichever form it arrives in.
library;

import '../core/models.dart';

/// An image in a message: its MIME type and either its base64 data or a
/// URL.
class ImageRef {
  ImageRef({required this.mimeType, this.base64Data, this.url});

  final String mimeType;
  final String? base64Data;
  final String? url;

  /// A `data:` URL when the data is inline, else the URL.
  String get dataUrl => base64Data != null ? 'data:$mimeType;base64,$base64Data' : url!;

  /// The image [content] holds — an [LlmImageContent] or its JSON
  /// (`{type: image, url | base64Data, mimeType}`) — or null.
  static ImageRef? of(Object? content) {
    String? url;
    String? data;
    String? mimeType;
    if (content is LlmImageContent) {
      url = content.url;
      data = content.base64Data;
      mimeType = content.mimeType;
    } else if (content is Map && content['type'] == 'image') {
      url = content['url'] as String?;
      data = content['base64Data'] as String? ?? content['data'] as String?;
      mimeType = content['mimeType'] as String?;
    } else {
      return null;
    }
    // A data URL carries the bytes itself.
    if (data == null && url != null && url.startsWith('data:')) {
      final comma = url.indexOf(',');
      final header = url.substring(5, comma);
      if (header.endsWith(';base64')) {
        data = url.substring(comma + 1);
        mimeType ??= header.substring(0, header.length - ';base64'.length);
      }
    }
    if (data == null && url == null) return null;
    return ImageRef(mimeType: mimeType ?? 'image/png', base64Data: data, url: data == null ? url : null);
  }
}
