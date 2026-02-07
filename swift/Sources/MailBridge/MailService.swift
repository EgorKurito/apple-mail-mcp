import Foundation

final class MailService {

    // MARK: - AppleScript Execution

    /// Execute AppleScript and return the result string
    private func runAppleScript(_ source: String) throws -> String {
        let script = NSAppleScript(source: source)!
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"

            // Error -1743: Not authorized to send Apple events
            if errorNumber == -1743 {
                throw BridgeError.mailAccessDenied
            }
            throw BridgeError.appleScriptError("\(errorMessage) (error \(errorNumber))")
        }

        return result.stringValue ?? ""
    }

    /// Execute AppleScript that returns a delimited list
    private func runAppleScriptList(_ source: String, delimiter: String = "|||") throws -> [String] {
        let result = try runAppleScript(source)
        if result.isEmpty { return [] }
        return result.components(separatedBy: delimiter)
    }

    // MARK: - Diagnostics

    func checkAccess() -> MailDiagnosticsInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersionString

        do {
            let accountNames = try runAppleScript("""
                tell application "Mail"
                    set accountNames to name of every account
                    set AppleScript's text item delimiters to "|||"
                    return accountNames as text
                end tell
            """)

            let names = accountNames.isEmpty ? [] : accountNames.components(separatedBy: "|||")
            return MailDiagnosticsInfo(
                mailAccess: "authorized",
                accountCount: names.count,
                accounts: names,
                macOSVersion: version
            )
        } catch let error as BridgeError {
            return MailDiagnosticsInfo(
                mailAccess: error.description,
                accountCount: 0,
                accounts: [],
                macOSVersion: version
            )
        } catch {
            return MailDiagnosticsInfo(
                mailAccess: "error: \(error.localizedDescription)",
                accountCount: 0,
                accounts: [],
                macOSVersion: version
            )
        }
    }

    // MARK: - Accounts

    func listAccounts() throws -> [MailAccountInfo] {
        // Get account data in batch — one AppleScript call with delimited output
        let script = """
            tell application "Mail"
                set output to ""
                repeat with acct in every account
                    set acctName to name of acct
                    set acctFullName to full name of acct
                    set acctEmails to email addresses of acct
                    set acctEnabled to enabled of acct
                    set acctType to ""
                    try
                        set acctType to (account type of acct) as text
                    end try

                    set AppleScript's text item delimiters to ";;;"
                    set emailStr to acctEmails as text

                    set rowData to acctName & ":::" & acctFullName & ":::" & emailStr & ":::" & acctType & ":::" & (acctEnabled as text)
                    if output is "" then
                        set output to rowData
                    else
                        set output to output & "|||" & rowData
                    end if
                end repeat
                return output
            end tell
        """

        let result = try runAppleScript(script)
        if result.isEmpty { return [] }

        let lines = result.components(separatedBy: "|||")
        return lines.enumerated().compactMap { (index, line) in
            let parts = line.components(separatedBy: ":::")
            guard parts.count >= 5 else { return nil }

            let emails = parts[2].isEmpty ? [] : parts[2].components(separatedBy: ";;;")
            return MailAccountInfo(
                id: "\(index)",
                name: parts[0],
                fullName: parts[1],
                emailAddresses: emails,
                accountType: parts[3],
                enabled: parts[4].lowercased() == "true"
            )
        }
    }

    // MARK: - Mailboxes

    func listMailboxes(accountName: String? = nil) throws -> [MailboxInfo] {
        // For simplicity, get flat mailbox list with counts
        // Recursive children require per-mailbox queries which are slow
        let script = """
            tell application "Mail"
                set output to ""
                \(accountName != nil ? "set accts to {account \"\(escapeAppleScript(accountName!))\"}" : "set accts to every account")
                repeat with acct in accts
                    set acctName to name of acct
                    repeat with mbox in mailboxes of acct
                        set mboxName to name of mbox
                        set unreadCnt to unread count of mbox
                        set msgCnt to count of messages of mbox
                        set childCount to count of mailboxes of mbox

                        set rowData to mboxName & ":::" & acctName & ":::" & (unreadCnt as text) & ":::" & (msgCnt as text) & ":::" & (childCount as text)
                        if output is "" then
                            set output to rowData
                        else
                            set output to output & "|||" & rowData
                        end if

                        -- Get children (one level deep)
                        if childCount > 0 then
                            repeat with childBox in mailboxes of mbox
                                set childName to name of childBox
                                set childUnread to unread count of childBox
                                set childMsgCnt to count of messages of childBox
                                set childChildCount to count of mailboxes of childBox

                                set childRow to childName & ":::" & acctName & ":::" & (childUnread as text) & ":::" & (childMsgCnt as text) & ":::" & (childChildCount as text) & ":::PARENT=" & mboxName
                                set output to output & "|||" & childRow
                            end repeat
                        end if
                    end repeat
                end repeat
                return output
            end tell
        """

        let result = try runAppleScript(script)
        if result.isEmpty { return [] }

        let lines = result.components(separatedBy: "|||")

        // Parse into flat list, then build tree
        struct RawMailbox {
            let name: String
            let account: String
            let unreadCount: Int
            let messageCount: Int
            let childCount: Int
            let parentName: String?
        }

        var rawBoxes: [RawMailbox] = []
        for line in lines {
            let parts = line.components(separatedBy: ":::")
            guard parts.count >= 5 else { continue }

            var parentName: String? = nil
            if parts.count >= 6, parts[5].hasPrefix("PARENT=") {
                parentName = String(parts[5].dropFirst(7))
            }

            rawBoxes.append(RawMailbox(
                name: parts[0],
                account: parts[1],
                unreadCount: Int(parts[2]) ?? 0,
                messageCount: Int(parts[3]) ?? 0,
                childCount: Int(parts[4]) ?? 0,
                parentName: parentName
            ))
        }

        // Build tree: top-level mailboxes with children
        var topLevel: [MailboxInfo] = []
        var childMap: [String: [MailboxInfo]] = [:]

        // First pass: collect children
        for raw in rawBoxes where raw.parentName != nil {
            let info = MailboxInfo(
                name: raw.name,
                fullName: "\(raw.account)/\(raw.parentName!)/\(raw.name)",
                account: raw.account,
                unreadCount: raw.unreadCount,
                messageCount: raw.messageCount,
                children: []
            )
            let key = "\(raw.account)/\(raw.parentName!)"
            childMap[key, default: []].append(info)
        }

        // Second pass: build top-level with children
        for raw in rawBoxes where raw.parentName == nil {
            let key = "\(raw.account)/\(raw.name)"
            let children = childMap[key] ?? []
            topLevel.append(MailboxInfo(
                name: raw.name,
                fullName: "\(raw.account)/\(raw.name)",
                account: raw.account,
                unreadCount: raw.unreadCount,
                messageCount: raw.messageCount,
                children: children
            ))
        }

        return topLevel
    }

    // MARK: - Messages

    func listMessages(mailbox: String, account: String? = nil, limit: Int = 50, offset: Int = 0) throws -> PaginatedMessages {
        let accountClause = account != nil
            ? "of account \"\(escapeAppleScript(account!))\""
            : ""

        // First get total count
        let countScript = """
            tell application "Mail"
                set mbox to mailbox "\(escapeAppleScript(mailbox))" \(accountClause)
                return (count of messages of mbox) as text
            end tell
        """
        let totalStr = try runAppleScript(countScript)
        let total = Int(totalStr) ?? 0

        if total == 0 {
            return PaginatedMessages(messages: [], total: 0, offset: offset, limit: limit, hasMore: false)
        }

        // Calculate range (newest first: messages are indexed 1-based, newest at end)
        let effectiveLimit = min(limit, 200)
        let startIdx = max(1, total - offset - effectiveLimit + 1)
        let endIdx = max(1, total - offset)

        if startIdx > endIdx || endIdx < 1 {
            return PaginatedMessages(messages: [], total: total, offset: offset, limit: effectiveLimit, hasMore: false)
        }

        // Batch fetch message properties
        let script = """
            tell application "Mail"
                set mbox to mailbox "\(escapeAppleScript(mailbox))" \(accountClause)
                set msgs to messages \(startIdx) thru \(endIdx) of mbox
                set output to ""
                repeat with msg in msgs
                    set msgId to id of msg
                    set msgMessageId to ""
                    try
                        set msgMessageId to message id of msg
                    end try
                    set msgSubject to subject of msg
                    set msgSender to sender of msg
                    set msgDateSent to date sent of msg
                    set msgDateReceived to date received of msg
                    set msgRead to read status of msg
                    set msgFlagged to flagged status of msg

                    set attachCount to 0
                    try
                        set attachCount to count of mail attachments of msg
                    end try

                    set rowData to (msgId as text) & ":::" & msgMessageId & ":::" & msgSubject & ":::" & msgSender & ":::" & (msgDateSent as text) & ":::" & (msgDateReceived as text) & ":::" & (msgRead as text) & ":::" & (msgFlagged as text) & ":::" & (attachCount as text)
                    if output is "" then
                        set output to rowData
                    else
                        set output to output & "|||" & rowData
                    end if
                end repeat
                return output
            end tell
        """

        let result = try runAppleScript(script)
        if result.isEmpty {
            return PaginatedMessages(messages: [], total: total, offset: offset, limit: effectiveLimit, hasMore: false)
        }

        let acctName = account ?? "Unknown"
        let lines = result.components(separatedBy: "|||")
        var headers: [MailMessageHeader] = []

        for line in lines {
            let parts = line.components(separatedBy: ":::")
            guard parts.count >= 9 else { continue }

            let senderRaw = parts[3]
            let parsed = parseSender(senderRaw)

            headers.append(MailMessageHeader(
                id: Int(parts[0]) ?? 0,
                messageId: parts[1],
                subject: parts[2],
                sender: senderRaw,
                senderName: parsed.name,
                senderEmail: parsed.email,
                dateSent: parts[4],
                dateReceived: parts[5],
                isRead: parts[6].lowercased() == "true",
                isFlagged: parts[7].lowercased() == "true",
                hasAttachments: (Int(parts[8]) ?? 0) > 0,
                mailbox: mailbox,
                account: acctName
            ))
        }

        // Reverse to get newest first
        headers.reverse()

        let hasMore = offset + effectiveLimit < total
        return PaginatedMessages(
            messages: headers,
            total: total,
            offset: offset,
            limit: effectiveLimit,
            hasMore: hasMore
        )
    }

    // MARK: - Message Detail

    func getMessage(messageId: Int, mailbox: String, account: String? = nil) throws -> MailMessageDetail {
        let accountClause = account != nil
            ? "of account \"\(escapeAppleScript(account!))\""
            : ""

        let script = """
            tell application "Mail"
                set mbox to mailbox "\(escapeAppleScript(mailbox))" \(accountClause)
                set msg to (first message of mbox whose id is \(messageId))

                set msgMessageId to ""
                try
                    set msgMessageId to message id of msg
                end try
                set msgSubject to subject of msg
                set msgSender to sender of msg
                set msgDateSent to date sent of msg as text
                set msgDateReceived to date received of msg as text
                set msgRead to read status of msg
                set msgFlagged to flagged status of msg
                set msgContent to ""
                try
                    set msgContent to content of msg
                end try

                -- Recipients
                set toList to ""
                try
                    set toAddrs to address of every to recipient of msg
                    set AppleScript's text item delimiters to ";;;"
                    set toList to toAddrs as text
                end try

                set ccList to ""
                try
                    set ccAddrs to address of every cc recipient of msg
                    set AppleScript's text item delimiters to ";;;"
                    set ccList to ccAddrs as text
                end try

                -- Attachments
                set attachInfo to ""
                try
                    repeat with att in mail attachments of msg
                        set attName to name of att
                        set attMime to MIME type of att
                        set attSize to file size of att
                        set attRow to attName & "~~~" & attMime & "~~~" & (attSize as text)
                        if attachInfo is "" then
                            set attachInfo to attRow
                        else
                            set attachInfo to attachInfo & ";;;" & attRow
                        end if
                    end repeat
                end try

                return (msgMessageId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDateSent & "|||" & msgDateReceived & "|||" & (msgRead as text) & "|||" & (msgFlagged as text) & "|||" & toList & "|||" & ccList & "|||" & attachInfo & "|||" & msgContent)
            end tell
        """

        let result = try runAppleScript(script)
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 11 else {
            throw BridgeError.messageNotFound(messageId)
        }

        let senderRaw = parts[2]
        let parsed = parseSender(senderRaw)
        let toRecipients = parts[7].isEmpty ? [] : parts[7].components(separatedBy: ";;;")
        let ccRecipients = parts[8].isEmpty ? [] : parts[8].components(separatedBy: ";;;")

        var attachments: [MailAttachmentInfo] = []
        if !parts[9].isEmpty {
            let attParts = parts[9].components(separatedBy: ";;;")
            for att in attParts {
                let attFields = att.components(separatedBy: "~~~")
                if attFields.count >= 3 {
                    attachments.append(MailAttachmentInfo(
                        name: attFields[0],
                        mimeType: attFields[1],
                        fileSize: Int(attFields[2]) ?? 0
                    ))
                }
            }
        }

        // Content is everything from index 10 onwards (may contain ||| in body)
        let content = parts.dropFirst(10).joined(separator: "|||")

        let acctName = account ?? "Unknown"
        return MailMessageDetail(
            id: messageId,
            messageId: parts[0],
            subject: parts[1],
            sender: senderRaw,
            senderName: parsed.name,
            senderEmail: parsed.email,
            toRecipients: toRecipients,
            ccRecipients: ccRecipients,
            dateSent: parts[3],
            dateReceived: parts[4],
            isRead: parts[5].lowercased() == "true",
            isFlagged: parts[6].lowercased() == "true",
            content: content,
            attachments: attachments,
            mailbox: mailbox,
            account: acctName
        )
    }

    // MARK: - Unread Messages

    func unreadMessages(account: String? = nil, mailbox: String? = nil, limit: Int = 50) throws -> [MailMessageHeader] {
        let effectiveLimit = min(limit, 200)

        let scope: String
        if let mbox = mailbox, let acct = account {
            scope = "mailbox \"\(escapeAppleScript(mbox))\" of account \"\(escapeAppleScript(acct))\""
        } else if let acct = account {
            // All mailboxes of specific account
            scope = "account \"\(escapeAppleScript(acct))\""
        } else {
            // All accounts — we iterate
            scope = ""
        }

        let script: String
        if scope.isEmpty {
            // Search across all accounts
            script = """
                tell application "Mail"
                    set output to ""
                    set msgCount to 0
                    repeat with acct in every account
                        if msgCount >= \(effectiveLimit) then exit repeat
                        set acctName to name of acct
                        repeat with mbox in mailboxes of acct
                            if msgCount >= \(effectiveLimit) then exit repeat
                            set unreadMsgs to (messages of mbox whose read status is false)
                            repeat with msg in unreadMsgs
                                if msgCount >= \(effectiveLimit) then exit repeat
                                set msgId to id of msg
                                set msgMessageId to ""
                                try
                                    set msgMessageId to message id of msg
                                end try
                                set msgSubject to subject of msg
                                set msgSender to sender of msg
                                set msgDateSent to date sent of msg as text
                                set msgDateReceived to date received of msg as text
                                set msgFlagged to flagged status of msg
                                set attachCount to 0
                                try
                                    set attachCount to count of mail attachments of msg
                                end try
                                set mboxName to name of mbox

                                set rowData to (msgId as text) & ":::" & msgMessageId & ":::" & msgSubject & ":::" & msgSender & ":::" & msgDateSent & ":::" & msgDateReceived & ":::" & (msgFlagged as text) & ":::" & (attachCount as text) & ":::" & mboxName & ":::" & acctName
                                if output is "" then
                                    set output to rowData
                                else
                                    set output to output & "|||" & rowData
                                end if
                                set msgCount to msgCount + 1
                            end repeat
                        end repeat
                    end repeat
                    return output
                end tell
            """
        } else if mailbox != nil {
            // Specific mailbox
            script = """
                tell application "Mail"
                    set output to ""
                    set mbox to \(scope)
                    set acctName to "\(escapeAppleScript(account ?? "Unknown"))"
                    set mboxName to "\(escapeAppleScript(mailbox!))"
                    set unreadMsgs to (messages of mbox whose read status is false)
                    set msgCount to 0
                    repeat with msg in unreadMsgs
                        if msgCount >= \(effectiveLimit) then exit repeat
                        set msgId to id of msg
                        set msgMessageId to ""
                        try
                            set msgMessageId to message id of msg
                        end try
                        set msgSubject to subject of msg
                        set msgSender to sender of msg
                        set msgDateSent to date sent of msg as text
                        set msgDateReceived to date received of msg as text
                        set msgFlagged to flagged status of msg
                        set attachCount to 0
                        try
                            set attachCount to count of mail attachments of msg
                        end try

                        set rowData to (msgId as text) & ":::" & msgMessageId & ":::" & msgSubject & ":::" & msgSender & ":::" & msgDateSent & ":::" & msgDateReceived & ":::" & (msgFlagged as text) & ":::" & (attachCount as text) & ":::" & mboxName & ":::" & acctName
                        if output is "" then
                            set output to rowData
                        else
                            set output to output & "|||" & rowData
                        end if
                        set msgCount to msgCount + 1
                    end repeat
                    return output
                end tell
            """
        } else {
            // All mailboxes of specific account
            script = """
                tell application "Mail"
                    set output to ""
                    set msgCount to 0
                    set acctName to "\(escapeAppleScript(account!))"
                    set acct to \(scope)
                    repeat with mbox in mailboxes of acct
                        if msgCount >= \(effectiveLimit) then exit repeat
                        set unreadMsgs to (messages of mbox whose read status is false)
                        set mboxName to name of mbox
                        repeat with msg in unreadMsgs
                            if msgCount >= \(effectiveLimit) then exit repeat
                            set msgId to id of msg
                            set msgMessageId to ""
                            try
                                set msgMessageId to message id of msg
                            end try
                            set msgSubject to subject of msg
                            set msgSender to sender of msg
                            set msgDateSent to date sent of msg as text
                            set msgDateReceived to date received of msg as text
                            set msgFlagged to flagged status of msg
                            set attachCount to 0
                            try
                                set attachCount to count of mail attachments of msg
                            end try

                            set rowData to (msgId as text) & ":::" & msgMessageId & ":::" & msgSubject & ":::" & msgSender & ":::" & msgDateSent & ":::" & msgDateReceived & ":::" & (msgFlagged as text) & ":::" & (attachCount as text) & ":::" & mboxName & ":::" & acctName
                            if output is "" then
                                set output to rowData
                            else
                                set output to output & "|||" & rowData
                            end if
                            set msgCount to msgCount + 1
                        end repeat
                    end repeat
                    return output
                end tell
            """
        }

        let result = try runAppleScript(script)
        if result.isEmpty { return [] }

        let lines = result.components(separatedBy: "|||")
        var headers: [MailMessageHeader] = []

        for line in lines {
            let parts = line.components(separatedBy: ":::")
            guard parts.count >= 10 else { continue }

            let senderRaw = parts[3]
            let parsed = parseSender(senderRaw)

            headers.append(MailMessageHeader(
                id: Int(parts[0]) ?? 0,
                messageId: parts[1],
                subject: parts[2],
                sender: senderRaw,
                senderName: parsed.name,
                senderEmail: parsed.email,
                dateSent: parts[4],
                dateReceived: parts[5],
                isRead: false,
                isFlagged: parts[6].lowercased() == "true",
                hasAttachments: (Int(parts[7]) ?? 0) > 0,
                mailbox: parts[8],
                account: parts[9]
            ))
        }

        return headers
    }

    // MARK: - Search

    func searchMessages(query: String, account: String? = nil, mailbox: String? = nil, limit: Int = 50) throws -> [MailMessageHeader] {
        let effectiveLimit = min(limit, 200)
        let escapedQuery = escapeAppleScript(query)

        // Search by subject and sender using whose clause
        let scope: String
        if let mbox = mailbox, let acct = account {
            scope = """
                set searchScope to {mailbox "\(escapeAppleScript(mbox))" of account "\(escapeAppleScript(acct))"}
            """
        } else if let acct = account {
            scope = """
                set searchScope to mailboxes of account "\(escapeAppleScript(acct))"
            """
        } else {
            scope = """
                set searchScope to {}
                repeat with acct in every account
                    repeat with mbox in mailboxes of acct
                        copy mbox to end of searchScope
                    end repeat
                end repeat
            """
        }

        let script = """
            tell application "Mail"
                \(scope)
                set output to ""
                set msgCount to 0
                repeat with mbox in searchScope
                    if msgCount >= \(effectiveLimit) then exit repeat
                    set mboxName to name of mbox
                    set acctName to name of account of mbox
                    try
                        set matchedMsgs to (messages of mbox whose subject contains "\(escapedQuery)" or sender contains "\(escapedQuery)")
                        repeat with msg in matchedMsgs
                            if msgCount >= \(effectiveLimit) then exit repeat
                            set msgId to id of msg
                            set msgMessageId to ""
                            try
                                set msgMessageId to message id of msg
                            end try
                            set msgSubject to subject of msg
                            set msgSender to sender of msg
                            set msgDateSent to date sent of msg as text
                            set msgDateReceived to date received of msg as text
                            set msgRead to read status of msg
                            set msgFlagged to flagged status of msg
                            set attachCount to 0
                            try
                                set attachCount to count of mail attachments of msg
                            end try

                            set rowData to (msgId as text) & ":::" & msgMessageId & ":::" & msgSubject & ":::" & msgSender & ":::" & msgDateSent & ":::" & msgDateReceived & ":::" & (msgRead as text) & ":::" & (msgFlagged as text) & ":::" & (attachCount as text) & ":::" & mboxName & ":::" & acctName
                            if output is "" then
                                set output to rowData
                            else
                                set output to output & "|||" & rowData
                            end if
                            set msgCount to msgCount + 1
                        end repeat
                    end try
                end repeat
                return output
            end tell
        """

        let result = try runAppleScript(script)
        if result.isEmpty { return [] }

        let lines = result.components(separatedBy: "|||")
        var headers: [MailMessageHeader] = []

        for line in lines {
            let parts = line.components(separatedBy: ":::")
            guard parts.count >= 11 else { continue }

            let senderRaw = parts[3]
            let parsed = parseSender(senderRaw)

            headers.append(MailMessageHeader(
                id: Int(parts[0]) ?? 0,
                messageId: parts[1],
                subject: parts[2],
                sender: senderRaw,
                senderName: parsed.name,
                senderEmail: parsed.email,
                dateSent: parts[4],
                dateReceived: parts[5],
                isRead: parts[6].lowercased() == "true",
                isFlagged: parts[7].lowercased() == "true",
                hasAttachments: (Int(parts[8]) ?? 0) > 0,
                mailbox: parts[9],
                account: parts[10]
            ))
        }

        return headers
    }

    // MARK: - Helpers

    private func escapeAppleScript(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
