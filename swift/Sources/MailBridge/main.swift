import ArgumentParser
import Foundation

@main
struct MailBridge: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-bridge",
        abstract: "Mail.app bridge for MCP server via NSAppleScript",
        subcommands: [
            MailDoctor.self,
            MailAccounts.self,
            Mailboxes.self,
            Messages.self,
            MessageDetail.self,
            UnreadMessages.self,
            SearchMail.self,
        ]
    )
}

// MARK: - Doctor

struct MailDoctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-doctor",
        abstract: "Check Mail.app access and diagnostics"
    )

    func run() {
        let service = MailService()
        let info = service.checkAccess()
        printJSON(BridgeOutput.success(info))
    }
}

// MARK: - Accounts

struct MailAccounts: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-accounts",
        abstract: "List mail accounts"
    )

    func run() {
        let service = MailService()
        do {
            let accounts = try service.listAccounts()
            printJSON(BridgeOutput.success(accounts))
        } catch {
            printError(error.localizedDescription)
        }
    }
}

// MARK: - Mailboxes

struct Mailboxes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mailboxes",
        abstract: "List mailboxes with message counts"
    )

    @Option(help: "Filter by account name")
    var account: String?

    func run() {
        let service = MailService()
        do {
            let mailboxes = try service.listMailboxes(accountName: account)
            printJSON(BridgeOutput.success(mailboxes))
        } catch {
            printError(error.localizedDescription)
        }
    }
}

// MARK: - Messages

struct Messages: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "messages",
        abstract: "List message headers from a mailbox"
    )

    @Option(help: "Mailbox name (e.g. INBOX)")
    var mailbox: String

    @Option(help: "Account name")
    var account: String?

    @Option(help: "Maximum messages to return (default 50, max 200)")
    var limit: Int = 50

    @Option(help: "Offset from newest (default 0)")
    var offset: Int = 0

    func run() {
        let service = MailService()
        do {
            let result = try service.listMessages(
                mailbox: mailbox,
                account: account,
                limit: limit,
                offset: offset
            )
            printJSON(BridgeOutput.success(result))
        } catch {
            printError(error.localizedDescription)
        }
    }
}

// MARK: - Message Detail

struct MessageDetail: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "message-detail",
        abstract: "Get full message content"
    )

    @Option(help: "Message ID")
    var id: Int

    @Option(help: "Mailbox name")
    var mailbox: String

    @Option(help: "Account name")
    var account: String?

    func run() {
        let service = MailService()
        do {
            let message = try service.getMessage(
                messageId: id,
                mailbox: mailbox,
                account: account
            )
            printJSON(BridgeOutput.success(message))
        } catch {
            printError(error.localizedDescription)
        }
    }
}

// MARK: - Unread Messages

struct UnreadMessages: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unread-messages",
        abstract: "List unread messages"
    )

    @Option(help: "Account name")
    var account: String?

    @Option(help: "Mailbox name")
    var mailbox: String?

    @Option(help: "Maximum messages to return (default 50, max 200)")
    var limit: Int = 50

    func run() {
        let service = MailService()
        do {
            let messages = try service.unreadMessages(
                account: account,
                mailbox: mailbox,
                limit: limit
            )
            printJSON(BridgeOutput.success(messages))
        } catch {
            printError(error.localizedDescription)
        }
    }
}

// MARK: - Search Mail

struct SearchMail: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search-mail",
        abstract: "Search messages by subject or sender"
    )

    @Option(help: "Search query")
    var query: String

    @Option(help: "Account name")
    var account: String?

    @Option(help: "Mailbox name")
    var mailbox: String?

    @Option(help: "Maximum messages to return (default 50, max 200)")
    var limit: Int = 50

    func run() {
        let service = MailService()
        do {
            let messages = try service.searchMessages(
                query: query,
                account: account,
                mailbox: mailbox,
                limit: limit
            )
            printJSON(BridgeOutput.success(messages))
        } catch {
            printError(error.localizedDescription)
        }
    }
}
