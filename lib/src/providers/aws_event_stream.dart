/// The AWS event stream framing (`application/vnd.amazon.eventstream`) that
/// Bedrock's `invoke-with-response-stream` answers with: binary messages of
/// prelude (total length, headers length, CRC), headers, payload and CRC.
library;

import 'dart:convert';
import 'dart:typed_data';

/// One decoded message: its string headers (`:event-type`,
/// `:message-type`, …) and payload bytes.
class AwsEventStreamMessage {
  AwsEventStreamMessage(this.headers, this.payload);

  final Map<String, String> headers;
  final Uint8List payload;
}

/// Decodes messages from bytes that arrive in arbitrary pieces: a message
/// split across network chunks is held until it is complete.
class AwsEventStreamDecoder {
  final List<int> _pending = [];

  /// Adds [bytes] and returns every message now complete.
  List<AwsEventStreamMessage> add(List<int> bytes) {
    _pending.addAll(bytes);
    final messages = <AwsEventStreamMessage>[];
    while (_pending.length >= 12) {
      final prelude = ByteData.sublistView(Uint8List.fromList(_pending.sublist(0, 12)));
      final totalLength = prelude.getUint32(0);
      final headersLength = prelude.getUint32(4);
      if (totalLength < 16 + headersLength) {
        throw const FormatException('AWS event stream: message length is smaller than its parts');
      }
      if (_pending.length < totalLength) break;
      final message = Uint8List.fromList(_pending.sublist(0, totalLength));
      _pending.removeRange(0, totalLength);
      messages.add(AwsEventStreamMessage(
        _headers(message, 12, 12 + headersLength),
        Uint8List.sublistView(message, 12 + headersLength, totalLength - 4),
      ));
    }
    return messages;
  }

  static Map<String, String> _headers(Uint8List bytes, int start, int end) {
    final data = ByteData.sublistView(bytes);
    final headers = <String, String>{};
    var i = start;
    while (i < end) {
      final nameLength = bytes[i];
      final name = utf8.decode(bytes.sublist(i + 1, i + 1 + nameLength));
      i += 1 + nameLength;
      final type = bytes[i];
      i += 1;
      switch (type) {
        case 0: // true
        case 1: // false
          break;
        case 2: // byte
          i += 1;
        case 3: // short
          i += 2;
        case 4: // integer
          i += 4;
        case 5: // long
        case 8: // timestamp
          i += 8;
        case 6: // byte array
        case 7: // string
          final length = data.getUint16(i);
          i += 2;
          if (type == 7) headers[name] = utf8.decode(bytes.sublist(i, i + length));
          i += length;
        case 9: // uuid
          i += 16;
        default:
          throw FormatException('AWS event stream: unknown header value type $type');
      }
    }
    return headers;
  }
}
