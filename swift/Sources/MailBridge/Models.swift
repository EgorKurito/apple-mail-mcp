import Foundation

// MARK: - Bridge Output Envelope

struct BridgeOutput<T: Encodable>: Encodable {
    let status: String
    let data: T?
    let error: String?

    static func success(_ data: T) -> BridgeOutput {
        BridgeOutput(status: "ok", data: data, error: nil)
    }

    static func failure(_ message: String) -> BridgeOutput<String> {
        BridgeOutput<String>(status: "error", data: nil, error: message)
    }
}

// MARK: - Mail Account

struct MailAccountInfo: Encodable {
    let id: String
    let name: String
    let fullName: String
    let emailAddresses: [String]
    let accountType: String
    let enabled: Bool
}

// MARK: - Mailbox

struct MailboxInfo: Encodable {
    let name: String
    let fullName: String
    let account: String
    let unreadCount: Int
    let messageCount: Int
    let children: [MailboxInfo]
}

// MARK: - Message Header (lightweight)

struct MailMessageHeader: Encodable {
    let id: Int
    let messageId: String
    let subject: String
    let sender: String
    let senderName: String
    let senderEmail: String
    let dateSent: String
    let dateReceived: String
    let isRead: Bool
    let isFlagged: Bool
    let hasAttachments: Bool
    let mailbox: String
    let account: String
}

// MARK: - Message Detail (full)

struct MailMessageDetail: Encodable {
    let id: Int
    let messageId: String
    let subject: String
    let sender: String
    let senderName: String
    let senderEmail: String
    let toRecipients: [String]
    let ccRecipients: [String]
    let dateSent: String
    let dateReceived: String
    let isRead: Bool
    let isFlagged: Bool
    let content: String
    let attachments: [MailAttachmentInfo]
    let mailbox: String
    let account: String
}

// MARK: - Attachment

struct MailAttachmentInfo: Encodable {
    let name: String
    let mimeType: String
    let fileSize: Int
}

// MARK: - Paginated Response

struct PaginatedMessages: Encodable {
    let messages: [MailMessageHeader]
    let total: Int
    let offset: Int
    let limit: Int
    let hasMore: Bool
}

// MARK: - Diagnostics

struct MailDiagnosticsInfo: Encodable {
    let mailAccess: String
    let accountCount: Int
    let accounts: [String]
    let macOSVersion: String
}

// MARK: - Bridge Error

enum BridgeError: Error, LocalizedError, CustomStringConvertible {
    case mailAccessDenied
    case accountNotFound(String)
    case mailboxNotFound(String)
    case messageNotFound(Int)
    case appleScriptError(String)
    case invalidParameter(String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .mailAccessDenied:
            return "Mail.app access denied. Grant access in System Settings > Privacy & Security > Automation."
        case .accountNotFound(let name):
            return "Mail account not found: \(name)"
        case .mailboxNotFound(let name):
            return "Mailbox not found: \(name)"
        case .messageNotFound(let id):
            return "Message not found: \(id)"
        case .appleScriptError(let msg):
            return "AppleScript error: \(msg)"
        case .invalidParameter(let msg):
            return "Invalid parameter: \(msg)"
        }
    }
}

// MARK: - JSON Helpers

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let isoFormatterNoFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func formatISO8601(_ date: Date) -> String {
    isoFormatter.string(from: date)
}

func printJSON<T: Encodable>(_ output: BridgeOutput<T>) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(output),
       let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

func printError(_ message: String) {
    printJSON(BridgeOutput<String>.failure(message))
}

// MARK: - Sender Parsing

/// Parse "Name <email>" format into (name, email) tuple
func parseSender(_ raw: String) -> (name: String, email: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)

    // Pattern: "Name <email@example.com>"
    if let angleBracketStart = trimmed.lastIndex(of: "<"),
       let angleBracketEnd = trimmed.lastIndex(of: ">"),
       angleBracketStart < angleBracketEnd {
        let email = String(trimmed[trimmed.index(after: angleBracketStart)..<angleBracketEnd])
            .trimmingCharacters(in: .whitespaces)
        let name = String(trimmed[trimmed.startIndex..<angleBracketStart])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (name: name.isEmpty ? email : name, email: email)
    }

    // Plain email
    if trimmed.contains("@") {
        return (name: trimmed, email: trimmed)
    }

    return (name: trimmed, email: "")
}
