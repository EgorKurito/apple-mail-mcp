import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { SwiftBridge } from "../bridge/swift.js";

export function registerMailTools(
  server: McpServer,
  bridge: SwiftBridge
): void {
  server.tool(
    "get_mail_accounts",
    "List all mail accounts (name, email, type, enabled)",
    {},
    async () => {
      try {
        const accounts = await bridge.accounts();
        return {
          content: [{ type: "text", text: JSON.stringify(accounts, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: String(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_mailboxes",
    "List mailboxes with unread/message counts and nested folders",
    {
      account: z
        .string()
        .optional()
        .describe("Filter by account name"),
    },
    async (args) => {
      try {
        const mailboxes = await bridge.mailboxes({ account: args.account });
        return {
          content: [
            { type: "text", text: JSON.stringify(mailboxes, null, 2) },
          ],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: String(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_messages",
    "Get message headers from a mailbox with pagination (newest first)",
    {
      mailbox: z.string().describe("Mailbox name (e.g. INBOX)"),
      account: z.string().optional().describe("Account name"),
      limit: z
        .number()
        .optional()
        .describe("Max messages to return (default 50, max 200)"),
      offset: z
        .number()
        .optional()
        .describe("Offset from newest (default 0)"),
    },
    async (args) => {
      try {
        const result = await bridge.messages({
          mailbox: args.mailbox,
          account: args.account,
          limit: args.limit,
          offset: args.offset,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: String(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_message",
    "Get full message content including body, recipients, and attachments",
    {
      id: z.number().describe("Message ID"),
      mailbox: z.string().describe("Mailbox name"),
      account: z.string().optional().describe("Account name"),
    },
    async (args) => {
      try {
        const message = await bridge.messageDetail({
          id: args.id,
          mailbox: args.mailbox,
          account: args.account,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(message, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: String(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_unread_messages",
    "List unread messages across all accounts or filtered by account/mailbox",
    {
      account: z.string().optional().describe("Filter by account name"),
      mailbox: z.string().optional().describe("Filter by mailbox name"),
      limit: z
        .number()
        .optional()
        .describe("Max messages to return (default 50, max 200)"),
    },
    async (args) => {
      try {
        const messages = await bridge.unreadMessages({
          account: args.account,
          mailbox: args.mailbox,
          limit: args.limit,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(messages, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: String(e) }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "search_mail",
    "Search messages by subject or sender",
    {
      query: z.string().describe("Search query (matches subject and sender)"),
      account: z.string().optional().describe("Filter by account name"),
      mailbox: z.string().optional().describe("Filter by mailbox name"),
      limit: z
        .number()
        .optional()
        .describe("Max messages to return (default 50, max 200)"),
    },
    async (args) => {
      try {
        const messages = await bridge.searchMail({
          query: args.query,
          account: args.account,
          mailbox: args.mailbox,
          limit: args.limit,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(messages, null, 2) }],
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: String(e) }],
          isError: true,
        };
      }
    }
  );
}
