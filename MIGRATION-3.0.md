# Moving to mcp_llm 3.0

Only the MCP layer changed; providers, chat, RAG, plugins and storage keep
their API. This guide lists every change that can stop 2.x code from
compiling or make it behave differently.

## 1. Authorization moved to the MCP client and server

Authorization is done by the MCP client and server; mcp_llm's own
authorization classes are removed:

| Removed | Instead |
|---|---|
| `McpAuthAdapter`, `AuthConfig`, `AuthResult`, `AuthContextManager`, `TokenValidator`, `ApiKeyValidator` (mcp_llm's own) | mcp_client: `StreamableHttpClientTransport.create(..., oauth: McpOAuth(McpOAuthOptions(...)))`, then hand the client to mcp_llm as before. mcp_server: `enableAuthentication` + `configureProtectedResource` |
| `LlmClientAdapter(client, authAdapter:, clientId:)` | `LlmClientAdapter(client)` |
| `LlmClientAdapter.authenticateClient`, `isAuthenticated`, `authContext`, `getAuthStatus`, `refreshToken`, `removeAuthentication`, `checkOAuth21Compliance` | the client's own authorization; an authorization failure is an `McpLayerException` with code -31001 and the challenge in `data` |
| `McpClientManager.addClientWithAuth`, `authenticatedClients`, `unauthenticatedClients`, `enableAuthenticationForClient`, `disableAuthenticationForClient`, `ensureAuthenticated`, `getAuthStatus`, `getAuthSummary`, `refreshAllTokens`, `checkOAuth21Compliance` | `addClient` with an authorized client |
| `McpServerManager.addServerWithAuth`, `authenticatedServers`, `unauthenticatedServers`, `getAuthSummary` | `addServer` with a server that has `enableAuthentication` |
| `authAdapter:` on `McpCapabilityManager.registerClient`, `McpHealthMonitor.registerClient`, `ServerLifecycleManager.registerServer` | dropped |
| `HealthCheckConfig(checkAuthentication: …)` | dropped |

## 2. MCP values are the protocol's types

| 2.x | 3.0 |
|---|---|
| adapter `CallToolResult` / `ReadResourceResult` / `GetPromptResult` | the generated types: `import 'package:mcp_llm/mcp_types.dart';` (a separate library, so it does not clash with mcp_client / mcp_server imports). Handlers may also return `LlmCallToolResult`, `LlmReadResourceResult`, `LlmGetPromptResult`, strings or protocol maps |
| `import 'package:mcp_llm/mcp_llm.dart' hide CallToolResult, ReadResourceResult, GetPromptResult;` (2.x needed it next to mcp_client / mcp_server) | drop the `hide`: `mcp_llm.dart` no longer exports these names, and hiding a name it does not export is the `undefined_hidden_name` warning |
| `CallToolResult.isStreaming` | not in the protocol |
| typed access | `adapter.bridge` / `manager.getBridge(id)` give `McpClientBridge` (`listTools`, `callTool`, `getPrompt`, `readResource`, `complete`, …) |

## 3. Failures are exceptions

| 2.x | 3.0 |
|---|---|
| `executeTool` / `readResource` / `executePrompt` returning `{'error': …}` | throw `McpLayerException` (`method`, `code`, `message`, `data`). A tool that ran and failed is still a result, with `isError: true` |
| `getTools(clientId)` returning `[]` when that client failed | throws; the all-clients form still skips (and logs) a failing client |
| `executeToolOnAllClients` values `{'error': …}` | the `McpLayerException` itself |
| mcp_llm-specific map keys | exact protocol JSON |

## 4. Other

| 2.x | 3.0 |
|---|---|
| `LlmClientAdapter.notifyCancelled(String id)` | `notifyCancelled(Object id)` — the JSON-RPC id of a request in flight |
| `ServiceRouter`, `ServiceBalancer`, `RoutingStrategy`, `ServiceFactory`, `LlmClientServiceAdapter`, `LlmServerServiceAdapter` | exported from `mcp_llm.dart` |
| `DefaultServiceBalancer` | smooth weighted round-robin (weights are honoured in proportion, interleaved) |

## 5. Sampling

`LlmClientAdapter(client).bindSamplingToLlm(provider, model: …)` answers a
server's `sampling/createMessage` with a provider (`McpSamplingHandler`) on
a client created with `ClientCapabilities(sampling: true)`. Images and
`stopSequences` in the request reach the provider; the provider's
configured model answers.

## 6. Capabilities and health records

| 2.x | 3.0 |
|---|---|
| capability `configuration: {tool_count: …}` | the declared capability object (`{listChanged: true}`); `version` is the negotiated revision |
| capability names `health_check`, `batch_processing`, `protocol_versioning` | the names the peer declares (`tools`, `resources`, `prompts`, `logging`, `completions`, …) |
| `McpCapabilityType.auth` / `batch` / `streaming` | deprecated; added `logging`, `completions`, `sampling`, `roots`, `elicitation`, `tasks`, `experimental`, `extensions` |
| health `metrics['capabilities']` | `metrics['kind']` (`client` / `server`), `protocolVersion`, `serverCapabilities` or `health` |
| system health `memory_usage`, `uptime` | `uptimeSeconds` |
| `ServerInfo.metadata['protocol_version']` | `version` (the server's own) |

## 7. Tool calls

- A call runs with the arguments the model gave; the server validates them
  against `inputSchema`. Code that relied on missing required arguments
  being filled with defaults should expect the tool's validation error.
- Calls with no arguments run with `{}`.
- Each call keeps one id from the model's turn to its result.
- `LlmToolCall.providerData` carries provider data (Gemini 3's
  `thoughtSignature`); keep it when you store and replay tool calls.
- `LlmServerAdapter.requestRoots` returns protocol JSON maps.

## 8. Providers

- `BedrockProvider(baseUrl:)` sets the runtime endpoint.
- Gemini / Vertex send tool schemas as `parametersJsonSchema`; the Gemini
  API key goes in the `x-goog-api-key` header.
- Stop sequences: `parameters['stop_sequences']` on every provider.
