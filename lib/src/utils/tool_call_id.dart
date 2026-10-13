/// Ids for tool calls a provider returned without one.
library;

int _next = 0;

/// A tool call id that no other call in this process shares. A provider that
/// returns several calls at once without ids (Gemini returns none) must
/// still give each its own: the tool results are matched back by id.
String syntheticToolCallId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_next++}';
