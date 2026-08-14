import DshNativeProtocol
import Foundation

struct WorkspaceListValue: Decodable, Sendable {
    let items: [Workspace]
}

struct Workspace: Decodable, Identifiable, Hashable, Sendable {
    let workspaceId: String
    let path: String
    let title: String
    let sessionIds: [String]

    var id: String { workspaceId }
}

struct SessionListValue: Decodable, Sendable {
    let items: [SessionSummary]
}

struct SessionSummary: Decodable, Identifiable, Sendable {
    struct Projections: Decodable, Sendable {
        let values: [String: JSONValue]
    }

    let sessionId: String
    let updatedAt: Double
    let running: Bool
    let blank: Bool
    let cwd: String?
    let projections: Projections?

    var id: String { sessionId }

    var title: String {
        if case let .string(title)? = projections?.values["title"], !title.isEmpty { return title }
        if let cwd, let name = URL(fileURLWithPath: cwd).pathComponents.last, !name.isEmpty { return name }
        return String(sessionId.prefix(8))
    }
}

struct SessionCreatePayload: Encodable, Sendable {
    let workspaceId: String?
    let cwd: String?
}

struct SessionCreateValue: Decodable, Sendable {
    let sessionId: String
}

struct SessionHistoryPayload: Encodable, Sendable {
    let sessionId: String
    let maxMessages: Int
}

struct SessionHistoryValue: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let event: SessionEvent
        let view: ToolEventView?
    }

    let events: [Entry]
}

struct SessionEvent: Decodable, Sendable {
    let type: String
    let seq: Int
    let time: Double
    let data: JSONValue
}

struct SessionPromptPayload: Encodable, Sendable {
    struct Part: Encodable, Sendable {
        let type = "text"
        let text: String
    }

    let sessionId: String
    let mode = "queue"
    let content: [Part]
}

struct SessionCancelPayload: Encodable, Sendable {
    let sessionId: String
}

struct AcceptedValue: Decodable, Sendable {
    let accepted: Bool
}

struct CredentialDescribePayload: Encodable, Sendable {
    let refs: [String]
}

struct CredentialView: Decodable, Equatable, Sendable {
    let configured: Bool
    let source: String?
    let writable: Bool
}

struct CredentialDescribeValue: Decodable, Sendable {
    let credentials: [String: CredentialView]
}

struct CredentialSetPayload: Encodable, Sendable {
    let ref: String
    let value: String
}

struct CredentialUnsetPayload: Encodable, Sendable {
    let ref: String
}

struct WorkspaceCreatePayload: Encodable, Sendable {
    let path: String
}

struct WorkspaceCreateValue: Decodable, Sendable {
    let workspace: Workspace
}

struct PendingApproval: Identifiable, Equatable, Sendable {
    let rpcId: String
    let sessionId: String
    let approvalId: String
    let toolName: String
    let callId: String?
    let reason: String?

    var id: String { "approval-\(rpcId)" }
}

struct PendingQuestion: Identifiable, Equatable, Sendable {
    struct Question: Identifiable, Equatable, Sendable {
        struct Option: Identifiable, Equatable, Sendable {
            let label: String
            let description: String?

            var id: String { label }
        }

        let id: String
        let question: String
        let detail: String?
        let header: String?
        let options: [Option]
        let multiSelect: Bool
    }

    let rpcId: String
    let sessionId: String
    let questions: [Question]

    var id: String { "question-\(rpcId)" }
}

enum PendingInteraction: Identifiable, Equatable, Sendable {
    case approval(PendingApproval)
    case question(PendingQuestion)

    var id: String {
        switch self {
        case let .approval(value): value.id
        case let .question(value): value.id
        }
    }

    var sessionId: String {
        switch self {
        case let .approval(value): value.sessionId
        case let .question(value): value.sessionId
        }
    }
}

struct ApprovalResponsePayload: Encodable, Sendable {
    let sessionId: String
    let approvalId: String
    let outcome: String
}

struct QuestionResponsePayload: Encodable, Sendable {
    struct Answer: Encodable, Sendable {
        struct Item: Encodable, Sendable {
            let id: String
            let selected: [String]
            let custom: String?
        }

        let answers: [Item]
    }

    let sessionId: String
    let answer: Answer
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
        case system
    }

    let id: String
    let role: Role
    var text: String
    var streaming: Bool
}

struct ToolEventView: Decodable, Equatable, Sendable {
    let `for`: String
    let view: JSONValue
}

struct ToolCard: Identifiable, Equatable, Sendable {
    let id: String
    let callId: String
    let name: String
    var title: String
    let arguments: String
    var detail: String
    var card: String
    var completed: Bool
    var isError: Bool
}

enum ConversationItem: Identifiable, Equatable, Sendable {
    case message(ChatMessage)
    case tool(ToolCard)

    var id: String {
        switch self {
        case let .message(message): message.id
        case let .tool(tool): tool.id
        }
    }
}

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case let .number(value) = self else { return nil }
        return Int(value)
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    func userVisibleText() -> String {
        guard objectValue?["source"]?.objectValue?["kind"]?.stringValue == "user" else { return "" }
        return textContent()
    }

    func assistantVisibleText() -> String {
        textContent()
    }

    func toolResultText() -> String {
        textBlocksContent()
    }

    func prettyPrinted() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return "" }
        return text
    }

    private func textContent() -> String {
        guard let blocks = objectValue?["content"]?.arrayValue else { return "" }
        return Self.text(from: blocks)
    }

    private func textBlocksContent() -> String {
        guard let blocks = arrayValue else { return textContent() }
        return Self.text(from: blocks)
    }

    private static func text(from blocks: [JSONValue]) -> String {
        return blocks.compactMap { block in
            guard let object = block.objectValue else { return nil }
            guard object["type"]?.stringValue == "text" else { return nil }
            return object["text"]?.stringValue
        }.joined(separator: "\n")
    }
}
