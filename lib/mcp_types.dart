/// The MCP protocol types mcp_llm uses (generated from the specification
/// schemas; the same shapes mcp_client and mcp_server carry). Import this
/// next to `package:mcp_llm/mcp_llm.dart` to name the typed results of
/// [McpClientBridge] and friends; it is kept separate so that importing
/// mcp_llm beside mcp_client does not clash on names like `Tool`.
library;

export 'src/schema/schema.g.dart';
