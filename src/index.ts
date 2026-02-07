#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SwiftBridge } from "./bridge/swift.js";
import { registerMailTools } from "./tools/mail.js";

const server = new McpServer({
  name: "apple-mail",
  version: "1.0.0",
});

const bridge = new SwiftBridge();
registerMailTools(server, bridge);

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("apple-mail MCP server running");
