import { execa } from "execa";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { existsSync } from "node:fs";

// Mirror of Swift models

export interface MailAccountInfo {
  id: string;
  name: string;
  fullName: string;
  emailAddresses: string[];
  accountType: string;
  enabled: boolean;
}

export interface MailboxInfo {
  name: string;
  fullName: string;
  account: string;
  unreadCount: number;
  messageCount: number;
  children: MailboxInfo[];
}

export interface MailMessageHeader {
  id: number;
  messageId: string;
  subject: string;
  sender: string;
  senderName: string;
  senderEmail: string;
  dateSent: string;
  dateReceived: string;
  isRead: boolean;
  isFlagged: boolean;
  hasAttachments: boolean;
  mailbox: string;
  account: string;
}

export interface MailMessageDetail {
  id: number;
  messageId: string;
  subject: string;
  sender: string;
  senderName: string;
  senderEmail: string;
  toRecipients: string[];
  ccRecipients: string[];
  dateSent: string;
  dateReceived: string;
  isRead: boolean;
  isFlagged: boolean;
  content: string;
  attachments: MailAttachmentInfo[];
  mailbox: string;
  account: string;
}

export interface MailAttachmentInfo {
  name: string;
  mimeType: string;
  fileSize: number;
}

export interface PaginatedMessages {
  messages: MailMessageHeader[];
  total: number;
  offset: number;
  limit: number;
  hasMore: boolean;
}

export interface MailDiagnosticsInfo {
  mailAccess: string;
  accountCount: number;
  accounts: string[];
  macOSVersion: string;
}

interface BridgeOutput<T> {
  status: "ok" | "error";
  data?: T;
  error?: string;
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

function findBinary(): string {
  const envPath = process.env.MAIL_BRIDGE_BIN;
  if (envPath) return envPath;

  // Auto-detect: relative to build/bridge/swift.js → ../../swift/.build/release/mail-bridge
  const autoPath = join(__dirname, "..", "..", "swift", ".build", "release", "mail-bridge");
  if (existsSync(autoPath)) return autoPath;

  throw new Error(
    "mail-bridge binary not found. Either set MAIL_BRIDGE_BIN environment variable " +
      "or run the postinstall script to build it: node scripts/postinstall.js"
  );
}

export class SwiftBridge {
  private binPath: string;

  constructor() {
    this.binPath = findBinary();
  }

  private async exec<T>(args: string[]): Promise<T> {
    const result = await execa(this.binPath, args, {
      reject: false,
      timeout: 60_000,
    });

    if (result.exitCode !== 0 && !result.stdout) {
      throw new Error(
        `mail-bridge failed (exit ${result.exitCode}): ${result.stderr}`
      );
    }

    const output: BridgeOutput<T> = JSON.parse(result.stdout);

    if (output.status === "error") {
      throw new Error(output.error ?? "Unknown bridge error");
    }

    return output.data as T;
  }

  async doctor(): Promise<MailDiagnosticsInfo> {
    return this.exec<MailDiagnosticsInfo>(["mail-doctor"]);
  }

  async accounts(): Promise<MailAccountInfo[]> {
    return this.exec<MailAccountInfo[]>(["mail-accounts"]);
  }

  async mailboxes(opts?: { account?: string }): Promise<MailboxInfo[]> {
    const args = ["mailboxes"];
    if (opts?.account) args.push("--account", opts.account);
    return this.exec<MailboxInfo[]>(args);
  }

  async messages(opts: {
    mailbox: string;
    account?: string;
    limit?: number;
    offset?: number;
  }): Promise<PaginatedMessages> {
    const args = ["messages", "--mailbox", opts.mailbox];
    if (opts.account) args.push("--account", opts.account);
    if (opts.limit !== undefined) args.push("--limit", String(opts.limit));
    if (opts.offset !== undefined) args.push("--offset", String(opts.offset));
    return this.exec<PaginatedMessages>(args);
  }

  async messageDetail(opts: {
    id: number;
    mailbox: string;
    account?: string;
  }): Promise<MailMessageDetail> {
    const args = [
      "message-detail",
      "--id",
      String(opts.id),
      "--mailbox",
      opts.mailbox,
    ];
    if (opts.account) args.push("--account", opts.account);
    return this.exec<MailMessageDetail>(args);
  }

  async unreadMessages(opts?: {
    account?: string;
    mailbox?: string;
    limit?: number;
  }): Promise<MailMessageHeader[]> {
    const args = ["unread-messages"];
    if (opts?.account) args.push("--account", opts.account);
    if (opts?.mailbox) args.push("--mailbox", opts.mailbox);
    if (opts?.limit !== undefined) args.push("--limit", String(opts.limit));
    return this.exec<MailMessageHeader[]>(args);
  }

  async searchMail(opts: {
    query: string;
    account?: string;
    mailbox?: string;
    limit?: number;
  }): Promise<MailMessageHeader[]> {
    const args = ["search-mail", "--query", opts.query];
    if (opts.account) args.push("--account", opts.account);
    if (opts.mailbox) args.push("--mailbox", opts.mailbox);
    if (opts.limit !== undefined) args.push("--limit", String(opts.limit));
    return this.exec<MailMessageHeader[]>(args);
  }
}
