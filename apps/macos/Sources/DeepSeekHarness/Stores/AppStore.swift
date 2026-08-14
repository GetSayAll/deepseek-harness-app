import DshNativeProtocol
import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    nonisolated static let deepSeekCredentialRef = "DEEPSEEK_API_KEY"

    enum ConnectionState: Equatable {
        case idle
        case starting
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .idle: "未连接"
            case .starting: "正在启动 Host…"
            case .ready: "Host 已连接"
            case let .failed(message): "连接失败：\(message)"
            }
        }
    }

    private let host = HostProcess()
    private let notifications = SystemNotificationService()
    private var hasStarted = false
    private var eventTask: Task<Void, Never>?

    var connectionState: ConnectionState = .idle
    var hostDescription: HostDescription?
    var hostVersion = "—"
    var capabilities: [String] = []
    var deepSeekCredential: CredentialView?
    var workspaces: [Workspace] = []
    var preferredWorkspaceId: String?
    var sessions: [SessionSummary] = []
    var agentPresets: [AgentPresetEntry] = []
    var selectedSessionId: String?
    var conversation: [ConversationItem] = []
    var pendingInteractions: [PendingInteraction] = []
    var selectedToolId: String?
    var draft = ""
    var isSending = false
    var isAgentPresetSaving = false
    var isCredentialSaving = false
    var errorMessage: String?

    var selectedSession: SessionSummary? {
        sessions.first { $0.sessionId == selectedSessionId }
    }

    var selectedPendingInteraction: PendingInteraction? {
        pendingInteractions.first { $0.sessionId == selectedSessionId }
    }

    var selectedAgentPresetId: String? {
        selectedSession?.agentPreset ?? agentPresets.first(where: \.isDefault)?.id
    }

    var selectedAgentPresetTitle: String {
        guard let selectedAgentPresetId else { return "通用助手" }
        return agentPresets.first { $0.id == selectedAgentPresetId }?.displayName ?? selectedAgentPresetId
    }

    var selectedTool: ToolCard? {
        conversation.compactMap { item -> ToolCard? in
            guard case let .tool(tool) = item, tool.id == selectedToolId else { return nil }
            return tool
        }.last
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await connect()
    }

    func restart() async {
        eventTask?.cancel()
        await host.stop()
        hasStarted = true
        await connect()
    }

    func stop() async {
        eventTask?.cancel()
        eventTask = nil
        await host.stop()
        connectionState = .idle
        hasStarted = false
        resetPendingInteractions()
    }

    private func connect() async {
        connectionState = .starting
        hostDescription = nil
        resetPendingInteractions()
        do {
            let hello = try await host.start()
            guard hello.protocolVersion == NativeProtocol.version else {
                throw NativeProtocolError.incompatibleVersion(
                    expected: NativeProtocol.version,
                    actual: hello.protocolVersion
                )
            }
            hostVersion = hello.appVersion
            capabilities = hello.capabilities
            let events = await host.events()
            eventTask = Task { [weak self] in
                for await event in events { await self?.handle(event) }
            }
            hostDescription = try await host.request(
                method: "host.describe",
                payload: EmptyPayload(),
                as: HostDescription.self
            )
            async let workspaceList = host.request(
                method: "workspace.list",
                payload: EmptyPayload(),
                as: WorkspaceListValue.self
            )
            async let sessionList = host.request(
                method: "session.list",
                payload: EmptyPayload(),
                as: SessionListValue.self
            )
            async let agentPresetList = host.request(
                method: "agentPreset.list",
                payload: EmptyPayload(),
                as: AgentPresetListValue.self
            )
            async let credentialDescription = host.request(
                method: "credentials.describe",
                payload: CredentialDescribePayload(refs: [Self.deepSeekCredentialRef]),
                as: CredentialDescribeValue.self
            )
            let (workspaceValue, sessionValue, presetValue, credentialValue) = try await (
                workspaceList,
                sessionList,
                agentPresetList,
                credentialDescription
            )
            workspaces = workspaceValue.items
            if !workspaces.contains(where: { $0.workspaceId == preferredWorkspaceId }) {
                preferredWorkspaceId = workspaces.first?.workspaceId
            }
            sessions = sessionValue.items.filter { !$0.blank }
            agentPresets = presetValue.presets
            deepSeekCredential = credentialValue.credentials[Self.deepSeekCredentialRef]
            selectedSessionId = selectedSessionId ?? sessions.first?.sessionId
            if let selectedSessionId { try await loadHistory(sessionId: selectedSessionId) }
            connectionState = .ready
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    func saveDeepSeekAPIKey(_ input: String) async -> Bool {
        let value: String
        do {
            value = try Self.normalizedAPIKey(input)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        isCredentialSaving = true
        defer { isCredentialSaving = false }
        do {
            _ = try await host.request(
                method: "credentials.set",
                payload: CredentialSetPayload(ref: Self.deepSeekCredentialRef, value: value),
                as: EmptyPayload.self
            )
            try await refreshDeepSeekCredential()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeDeepSeekAPIKey() async {
        isCredentialSaving = true
        defer { isCredentialSaving = false }
        do {
            _ = try await host.request(
                method: "credentials.unset",
                payload: CredentialUnsetPayload(ref: Self.deepSeekCredentialRef),
                as: EmptyPayload.self
            )
            try await refreshDeepSeekCredential()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshDeepSeekCredential() async throws {
        let value = try await host.request(
            method: "credentials.describe",
            payload: CredentialDescribePayload(refs: [Self.deepSeekCredentialRef]),
            as: CredentialDescribeValue.self
        )
        deepSeekCredential = value.credentials[Self.deepSeekCredentialRef]
    }

    nonisolated static func normalizedAPIKey(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw NativeProtocolError.host("请输入 DeepSeek API Key")
        }
        guard !value.contains("="), value.unicodeScalars.allSatisfy({ 0x21...0x7E ~= $0.value }) else {
            throw NativeProtocolError.host("API Key 格式无效；请只粘贴 Key 本身")
        }
        return value
    }

    func selectSession(_ sessionId: String?) async {
        guard selectedSessionId != sessionId else { return }
        selectedSessionId = sessionId
        selectedToolId = nil
        conversation = []
        guard let sessionId else { return }
        do { try await loadHistory(sessionId: sessionId) }
        catch { errorMessage = error.localizedDescription }
    }

    func newSession(workspaceId: String? = nil) async {
        do {
            let value = try await host.request(
                method: "session.create",
                payload: SessionCreatePayload(workspaceId: workspaceId, cwd: workspaceId == nil ? hostDescription?.cwd : nil),
                as: SessionCreateValue.self
            )
            let list = try await host.request(
                method: "session.list",
                payload: EmptyPayload(),
                as: SessionListValue.self
            )
            sessions = list.items
            selectedSessionId = value.sessionId
            selectedToolId = nil
            conversation = []
        } catch { errorMessage = error.localizedDescription }
    }

    func addWorkspace() async {
        guard let url = DirectoryPicker.choose() else { return }
        do {
            let value = try await host.request(
                method: "workspace.create",
                payload: WorkspaceCreatePayload(path: url.path),
                as: WorkspaceCreateValue.self
            )
            if !workspaces.contains(where: { $0.id == value.workspace.id }) { workspaces.append(value.workspace) }
            preferredWorkspaceId = value.workspace.workspaceId
            await newSession(workspaceId: value.workspace.workspaceId)
        } catch { errorMessage = error.localizedDescription }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if selectedSessionId == nil {
            guard let workspaceId = preferredWorkspaceId ?? workspaces.first?.workspaceId else {
                errorMessage = "请先添加并选择一个工作区。"
                return
            }
            await newSession(workspaceId: workspaceId)
        }
        guard let selectedSessionId else { return }
        draft = ""
        isSending = true
        do {
            _ = try await host.request(
                method: "session.prompt",
                payload: SessionPromptPayload(sessionId: selectedSessionId, content: [.init(text: text)]),
                as: AcceptedValue.self
            )
        } catch {
            errorMessage = error.localizedDescription
            isSending = false
        }
    }

    func cancel() async {
        guard let selectedSessionId else { return }
        do {
            _ = try await host.request(
                method: "session.cancel",
                payload: SessionCancelPayload(sessionId: selectedSessionId),
                as: AcceptedValue.self
            )
        } catch { errorMessage = error.localizedDescription }
    }

    func selectTool(_ tool: ToolCard?) {
        selectedToolId = tool?.id
    }

    func selectAgentPreset(_ agentPreset: String) async {
        guard let selectedSessionId,
              let index = sessions.firstIndex(where: { $0.sessionId == selectedSessionId }),
              sessions[index].blank else {
            errorMessage = "会话开始后不能更换助手。"
            return
        }
        isAgentPresetSaving = true
        defer { isAgentPresetSaving = false }
        do {
            let value = try await host.request(
                method: "agentPreset.select",
                payload: AgentPresetSelectPayload(sessionId: selectedSessionId, agentPreset: agentPreset),
                as: AgentPresetSelectValue.self
            )
            let summary = sessions[index]
            sessions[index] = SessionSummary(
                sessionId: summary.sessionId,
                updatedAt: summary.updatedAt,
                running: summary.running,
                blank: summary.blank,
                cwd: summary.cwd,
                agentPreset: value.agentPreset,
                projections: summary.projections
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func answerApproval(_ approval: PendingApproval, outcome: String) async {
        do {
            try await host.respond(
                rpcId: approval.rpcId,
                value: ApprovalResponsePayload(
                    sessionId: approval.sessionId,
                    approvalId: approval.approvalId,
                    outcome: outcome
                )
            )
        } catch { errorMessage = error.localizedDescription }
    }

    func answerQuestion(_ question: PendingQuestion, answers: [QuestionResponsePayload.Answer.Item]) async {
        do {
            try await host.respond(
                rpcId: question.rpcId,
                value: QuestionResponsePayload(
                    sessionId: question.sessionId,
                    answer: .init(answers: answers)
                )
            )
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelQuestion(_ question: PendingQuestion) async {
        do { try await host.cancelResponse(rpcId: question.rpcId) }
        catch { errorMessage = error.localizedDescription }
    }

    private func loadHistory(sessionId: String) async throws {
        let value = try await host.request(
            method: "session.history",
            payload: SessionHistoryPayload(sessionId: sessionId, maxMessages: 100),
            as: SessionHistoryValue.self
        )
        conversation = Self.fold(value.events)
    }

    private func handle(_ frame: NativeEventFrame) async {
        guard let payload = frame.value.payload.objectValue else { return }
        switch frame.value.method {
        case "session/event":
            guard payload["sessionId"]?.stringValue == selectedSessionId,
                  let eventValue = payload["event"],
                  let data = try? JSONEncoder().encode(eventValue),
                  let event = try? JSONDecoder().decode(SessionEvent.self, from: data)
            else { return }
            apply(event, view: payload["view"])
        case "approval/requested":
            guard let approval = Self.approval(rpcId: frame.value.rpcId, payload: payload) else { return }
            if replacePending(.approval(approval)) {
                notifications.notifyApproval(
                    sessionId: approval.sessionId,
                    approvalId: approval.approvalId,
                    selectedSessionId: selectedSessionId
                )
            }
        case "approval/resolved":
            guard let approvalId = payload["approvalId"]?.stringValue else { return }
            pendingInteractions.removeAll {
                guard case let .approval(approval) = $0 else { return false }
                return approval.approvalId == approvalId
            }
            notifications.removeApproval(approvalId: approvalId)
            syncPendingInteractionBadge()
        case "question/requested":
            guard let question = Self.question(rpcId: frame.value.rpcId, payload: payload) else { return }
            if replacePending(.question(question)) {
                notifications.notifyQuestion(
                    sessionId: question.sessionId,
                    rpcId: question.rpcId,
                    selectedSessionId: selectedSessionId
                )
            }
        case "question/resolved":
            guard let rpcId = payload["questionRpcId"]?.stringValue else { return }
            pendingInteractions.removeAll {
                guard case let .question(question) = $0 else { return false }
                return question.rpcId == rpcId
            }
            notifications.removeQuestion(rpcId: rpcId)
            syncPendingInteractionBadge()
        case "host/session-status":
            guard let sessionId = payload["sessionId"]?.stringValue,
                  case let .bool(running)? = payload["running"] else { return }
            let wasRunning = sessions.first { $0.sessionId == sessionId }?.running
            sessions = sessions.map { summary in
                guard summary.sessionId == sessionId else { return summary }
                return SessionSummary(
                    sessionId: summary.sessionId,
                    updatedAt: summary.updatedAt,
                    running: running,
                    blank: summary.blank,
                    cwd: summary.cwd,
                    agentPreset: summary.agentPreset,
                    projections: summary.projections
                )
            }
            if sessionId == selectedSessionId, !running { isSending = false }
            if wasRunning == true, !running {
                notifications.notifyTurnEnded(
                    sessionId: sessionId,
                    selectedSessionId: selectedSessionId
                )
            }
        case "host/session-added":
            let list = try? await host.request(method: "session.list", payload: EmptyPayload(), as: SessionListValue.self)
            if let list { sessions = list.items }
        case "host/workspace-changed":
            let list = try? await host.request(method: "workspace.list", payload: EmptyPayload(), as: WorkspaceListValue.self)
            if let list { workspaces = list.items }
        default:
            break
        }
    }

    private func apply(_ event: SessionEvent, view: JSONValue? = nil) {
        switch event.type {
        case "user/message":
            let text = event.data.userVisibleText()
            guard !text.isEmpty, !conversation.contains(where: { $0.id == String(event.seq) }) else { return }
            conversation.append(.message(ChatMessage(id: String(event.seq), role: .user, text: text, streaming: false)))
        case "assistant/chunk":
            guard let chunk = event.data.objectValue?["chunk"]?.objectValue,
                  chunk["type"]?.stringValue == "text-delta",
                  let text = chunk["text"]?.stringValue else { return }
            if let index = streamingAssistantIndex,
               case var .message(message) = conversation[index] {
                message.text += text
                conversation[index] = .message(message)
            } else {
                conversation.append(.message(ChatMessage(id: "stream-\(event.seq)", role: .assistant, text: text, streaming: true)))
            }
        case "assistant/message":
            guard let message = event.data.objectValue?["message"] else { return }
            let text = message.assistantVisibleText()
            if let index = streamingAssistantIndex,
               case var .message(streaming) = conversation[index] {
                streaming.text = text
                streaming.streaming = false
                conversation[index] = .message(streaming)
            } else if !text.isEmpty {
                conversation.append(.message(ChatMessage(id: String(event.seq), role: .assistant, text: text, streaming: false)))
            }
        case "tool/call":
            guard let card = Self.toolCall(event, view: view) else { return }
            conversation.append(.tool(card))
        case "tool/result":
            Self.applyToolResult(event, view: view, to: &conversation)
        case "turn/end":
            isSending = false
        default:
            break
        }
    }

    private var streamingAssistantIndex: Int? {
        conversation.lastIndex {
            guard case let .message(message) = $0 else { return false }
            return message.role == .assistant && message.streaming
        }
    }

    static func fold(_ entries: [SessionHistoryValue.Entry]) -> [ConversationItem] {
        var result: [ConversationItem] = []
        for entry in entries {
            let event = entry.event
            switch event.type {
            case "user/message":
                let text = event.data.userVisibleText()
                if !text.isEmpty { result.append(.message(.init(id: String(event.seq), role: .user, text: text, streaming: false))) }
            case "assistant/message":
                guard let message = event.data.objectValue?["message"] else { continue }
                let text = message.assistantVisibleText()
                if !text.isEmpty { result.append(.message(.init(id: String(event.seq), role: .assistant, text: text, streaming: false))) }
            case "tool/call":
                if let card = toolCall(event, view: entry.view?.view) { result.append(.tool(card)) }
            case "tool/result":
                applyToolResult(event, view: entry.view?.view, to: &result)
            default:
                continue
            }
        }
        return result
    }

    private static func toolCall(_ event: SessionEvent, view: JSONValue?) -> ToolCard? {
        guard let data = event.data.objectValue,
              let callId = data["callId"]?.stringValue,
              let name = data["name"]?.stringValue,
              let arguments = data["arguments"]?.stringValue else { return nil }
        let intent = toolIntent(view)
        return ToolCard(
            id: "tool-\(callId)",
            callId: callId,
            name: name,
            title: intent?["title"]?.stringValue ?? name,
            arguments: arguments,
            detail: intent?["description"]?.stringValue ?? prettyArguments(arguments),
            card: intent?["card"]?.stringValue ?? "generic",
            completed: false,
            isError: false
        )
    }

    private static func applyToolResult(_ event: SessionEvent, view: JSONValue?, to items: inout [ConversationItem]) {
        guard let data = event.data.objectValue,
              let message = data["message"]?.objectValue,
              let source = message["source"]?.objectValue,
              let callId = source["callId"]?.stringValue else { return }
        let intent = toolIntent(view)
        let fallback = message["content"]?.arrayValue?.compactMap { block -> String? in
            guard let object = block.objectValue,
                  object["type"]?.stringValue == "tool-result" else { return nil }
            return object["content"]?.toolResultText()
        }.joined(separator: "\n") ?? ""
        let detail = intent?["output"]?.stringValue
            ?? intent?["content"]?.toolResultText()
            ?? fallback
        let index = items.lastIndex {
            guard case let .tool(card) = $0 else { return false }
            return card.callId == callId
        }
        let isError = message["content"]?.arrayValue?.contains {
            $0.objectValue?["isError"] == .bool(true)
        } ?? (data["error"] != nil)
        if let index, case var .tool(card) = items[index] {
            card.title = intent?["title"]?.stringValue ?? card.title
            card.detail = detail.isEmpty ? card.detail : detail
            card.card = intent?["card"]?.stringValue ?? card.card
            card.completed = true
            card.isError = isError
            items[index] = .tool(card)
        } else {
            items.append(.tool(ToolCard(
                id: "tool-\(callId)",
                callId: callId,
                name: "未知工具",
                title: intent?["title"]?.stringValue ?? "工具结果",
                arguments: "",
                detail: detail,
                card: intent?["card"]?.stringValue ?? "generic",
                completed: true,
                isError: isError
            )))
        }
    }

    private static func toolIntent(_ value: JSONValue?) -> [String: JSONValue]? {
        guard let object = value?.objectValue else { return nil }
        return object["view"]?.objectValue ?? object
    }

    private static func prettyArguments(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return arguments }
        return text
    }

    @discardableResult
    private func replacePending(_ interaction: PendingInteraction) -> Bool {
        let inserted = !pendingInteractions.contains { $0.id == interaction.id }
        pendingInteractions.removeAll { $0.id == interaction.id }
        pendingInteractions.append(interaction)
        syncPendingInteractionBadge()
        return inserted
    }

    private func syncPendingInteractionBadge() {
        notifications.setPendingInteractionCount(pendingInteractions.count)
    }

    private func resetPendingInteractions() {
        for interaction in pendingInteractions {
            switch interaction {
            case let .approval(approval):
                notifications.removeApproval(approvalId: approval.approvalId)
            case let .question(question):
                notifications.removeQuestion(rpcId: question.rpcId)
            }
        }
        pendingInteractions = []
        syncPendingInteractionBadge()
    }

    static func approval(rpcId: String, payload: [String: JSONValue]) -> PendingApproval? {
        guard let sessionId = payload["sessionId"]?.stringValue,
              let approvalId = payload["approvalId"]?.stringValue,
              let toolName = payload["toolName"]?.stringValue else { return nil }
        return PendingApproval(
            rpcId: rpcId,
            sessionId: sessionId,
            approvalId: approvalId,
            toolName: toolName,
            callId: payload["callId"]?.stringValue,
            reason: payload["reason"]?.stringValue
        )
    }

    static func question(rpcId: String, payload: [String: JSONValue]) -> PendingQuestion? {
        guard let sessionId = payload["sessionId"]?.stringValue,
              let values = payload["questions"]?.arrayValue else { return nil }
        let questions = values.compactMap { value -> PendingQuestion.Question? in
            guard let object = value.objectValue,
                  let id = object["id"]?.stringValue,
                  let text = object["question"]?.stringValue else { return nil }
            let options = object["options"]?.arrayValue?.compactMap { option -> PendingQuestion.Question.Option? in
                guard let fields = option.objectValue,
                      let label = fields["label"]?.stringValue else { return nil }
                return .init(label: label, description: fields["description"]?.stringValue)
            } ?? []
            return .init(
                id: id,
                question: text,
                detail: object["detail"]?.stringValue,
                header: object["header"]?.stringValue,
                options: options,
                multiSelect: object["multiSelect"]?.boolValue ?? false
            )
        }
        guard questions.count == values.count, !questions.isEmpty else { return nil }
        return PendingQuestion(rpcId: rpcId, sessionId: sessionId, questions: questions)
    }

}
