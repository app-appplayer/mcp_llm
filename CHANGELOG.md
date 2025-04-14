## 0.2.1
## 0.2.0

* Multi-MCP Client Support (New Feature)
    * Added McpClientManager class to manage multiple MCP clients within a single LLM client
    * Enhanced LLM clients to work with multiple MCP clients identified by string IDs
    * Implemented intelligent routing of tool calls to the most appropriate MCP client
    * Added schema matching algorithm to select the best client for each tool
* Multi-LLM Client Support (Existing Feature)
    * Maintained MultiClientManager for managing multiple LLM clients
    * Preserved query routing, load balancing, and fan-out capabilities
    * Kept the ability to manage multiple LLM clients from a single McpLlm instance
* LLM Provider Multi Language Support
* API Additions
    * Added mcpClients parameter to createClient method for initializing with multiple MCP clients
    * New MCP client management methods:
    * addMcpClient, removeMcpClient, setDefaultMcpClient
    * getMcpClientIds, findMcpClientsWithTool, getToolsByClient
    * New tool execution methods:
    * executeToolWithSpecificClient: Execute a tool on a specific MCP client
    * executeToolOnAllMcpClients: Execute a tool on all MCP clients and collect results
*Compatibility Notes
    * All changes maintain backward compatibility with existing code
    * Single MCP client approach continues to be supported
    * New multi-client functionality is available as an opt-in feature
 
## 0.1.0

* Initial release
* Features:
    * Multiple LLM provider support (Claude, OpenAI, Together AI)
    * Multi-client management with routing and load balancing
    * Parallel processing across multiple LLM providers
    * Plugin system for custom tools and templates
    * Document storage and RAG capabilities
    * Performance monitoring and task scheduling
* Known limitations:
    * API still subject to significant changes
    * Limited test coverage
    * Some providers may have incomplete implementations
    * Documentation is preliminary
