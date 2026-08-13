import DshNativeProtocol
import Foundation

actor HostProcess {
    private struct ResponseHeader: Decodable {
        let id: String?
        let type: String
    }

    private var process: Process?
    private var input: FileHandle?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    private var eventContinuation: AsyncStream<NativeEventFrame>.Continuation?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func start() async throws -> HelloResponse {
        if process != nil { await stop() }

        let launch = try Self.launchConfiguration()
        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        child.executableURL = launch.node
        child.arguments = launch.arguments
        child.currentDirectoryURL = launch.workingDirectory
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = stderrPipe

        process = child
        input = stdinPipe.fileHandleForWriting
        outputHandle = stdoutPipe.fileHandleForReading
        outputHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receiveOutput(data) }
        }
        Task { await forwardDiagnostics(stderrPipe.fileHandleForReading) }

        do {
            try child.run()
        } catch {
            process = nil
            input = nil
            closeOutput()
            throw error
        }

        child.terminationHandler = { process in
            Task { await self.processExited(process.terminationStatus) }
        }

        return try await exchange(HelloRequest(), as: HelloResponse.self)
    }

    func request<Payload: Encodable & Sendable, Value: Decodable & Sendable>(
        method: String,
        payload: Payload,
        as type: Value.Type
    ) async throws -> Value {
        let response = try await exchange(
            UnaryRequest(method: method, payload: payload),
            as: TransportResponse<ServerResponse<Value>>.self
        )
        if let error = response.error {
            throw NativeProtocolError.host("\(error.code): \(error.message)")
        }
        guard let server = response.value else { throw NativeProtocolError.malformedResponse }
        switch server.result {
        case let .success(value): return value
        case let .failure(code, message): throw NativeProtocolError.host("\(code): \(message)")
        }
    }

    func events() -> AsyncStream<NativeEventFrame> {
        AsyncStream { continuation in
            eventContinuation = continuation
        }
    }

    func respond<Payload: Encodable & Sendable>(rpcId: String, value: Payload) async throws {
        let response = try await exchange(
            NativeRespondRequest(rpcId: rpcId, result: ClientSuccess(value: value)),
            as: TransportResponse<RpcReceipt>.self
        )
        try accept(response)
    }

    func cancelResponse(rpcId: String) async throws {
        let response = try await exchange(
            NativeRespondRequest(
                rpcId: rpcId,
                result: ClientFailure(code: "cancelled", message: "The user cancelled the request")
            ),
            as: TransportResponse<RpcReceipt>.self
        )
        try accept(response)
    }

    func stop() async {
        guard let child = process else { return }
        if child.isRunning {
            do {
                _ = try await exchange(
                    ShutdownRequest(),
                    as: TransportResponse<EmptyPayload>.self
                )
            } catch {
                child.terminate()
            }
        }
        if child.isRunning { _ = await waitForExit() }
        process = nil
        input = nil
        closeOutput()
    }

    private func exchange<Request: Encodable, Response: Decodable>(
        _ request: Request,
        as type: Response.Type
    ) async throws -> Response {
        guard let input else { throw NativeProtocolError.host("Host process is not running") }
        let id = try requestID(request)
        let data = try encoder.encode(request)
        let responseData = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try input.write(contentsOf: data + Data([0x0A]))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
        return try decoder.decode(type, from: responseData)
    }

    private func requestID<Request: Encodable>(_ request: Request) throws -> String {
        let data = try encoder.encode(request)
        guard let id = try decoder.decode(ResponseHeader.self, from: data).id else {
            throw NativeProtocolError.malformedResponse
        }
        return id
    }

    private func accept(_ response: TransportResponse<RpcReceipt>) throws {
        if let error = response.error {
            throw NativeProtocolError.host("\(error.code): \(error.message)")
        }
        guard let receipt = response.value else { throw NativeProtocolError.malformedResponse }
        guard receipt.accepted else {
            throw NativeProtocolError.host("Host 不再等待此响应：\(receipt.reason ?? "未知原因")")
        }
    }

    private func receiveOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        outputBuffer.append(data)
        do {
            while let newline = outputBuffer.firstIndex(of: 0x0A) {
                let line = outputBuffer[..<newline]
                outputBuffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                let header = try decoder.decode(ResponseHeader.self, from: line)
                if header.type == "event" {
                    eventContinuation?.yield(try decoder.decode(NativeEventFrame.self, from: line))
                    continue
                }
                guard let id = header.id else { continue }
                pending.removeValue(forKey: id)?.resume(returning: Data(line))
            }
        } catch {
            failPending(error)
        }
    }

    private func forwardDiagnostics(_ handle: FileHandle) async {
        do {
            for try await line in handle.bytes.lines {
                FileHandle.standardError.write(Data("[dsh-host] \(line)\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("[dsh-host] log stream failed: \(error)\n".utf8))
        }
    }

    private func processExited(_ status: Int32) {
        process = nil
        input = nil
        closeOutput()
        eventContinuation?.finish()
        eventContinuation = nil
        failPending(NativeProtocolError.processExited(status))
        let waiters = exitWaiters
        exitWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: status) }
    }

    private func failPending(_ error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
    }

    private func closeOutput() {
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        outputBuffer.removeAll(keepingCapacity: true)
    }

    private func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            exitWaiters.append(continuation)
        }
    }

    private struct LaunchConfiguration {
        let node: URL
        let arguments: [String]
        let workingDirectory: URL
    }

    private static func launchConfiguration() throws -> LaunchConfiguration {
        let environment = ProcessInfo.processInfo.environment
        if let configuredRoot = environment["DSH_MACOS_REPOSITORY_ROOT"] {
            let root = URL(fileURLWithPath: configuredRoot, isDirectory: true)
            let node = try developmentNode(environment["DSH_NODE_PATH"])
            return LaunchConfiguration(
                node: node,
                arguments: ["--import", "tsx/esm", root.appending(path: "apps/macos/Host/sidecar.ts").path],
                workingDirectory: root
            )
        }

        guard let resources = Bundle.main.resourceURL else {
            throw NativeProtocolError.host("应用包缺少 Resources 目录")
        }
        let runtime = resources.appending(path: "runtime", directoryHint: .isDirectory)
        let node = runtime.appending(path: "node/bin/node")
        let app = runtime.appending(path: "app", directoryHint: .isDirectory)
        let sidecar = app.appending(path: "lib/sidecar.js")
        guard FileManager.default.isExecutableFile(atPath: node.path) else {
            throw NativeProtocolError.host("应用包缺少内置 Node.js 运行时")
        }
        guard FileManager.default.fileExists(atPath: sidecar.path) else {
            throw NativeProtocolError.host("应用包缺少 Host sidecar")
        }
        return LaunchConfiguration(node: node, arguments: [sidecar.path], workingDirectory: app)
    }

    private static func developmentNode(_ configuredPath: String?) throws -> URL {
        if let configuredPath { return URL(fileURLWithPath: configuredPath) }
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw NativeProtocolError.host("开发环境找不到 Node.js；请设置 DSH_NODE_PATH")
    }

}
