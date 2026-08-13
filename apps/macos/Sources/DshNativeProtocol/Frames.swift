import Foundation

public enum NativeProtocolError: Error, Equatable, Sendable {
    case incompatibleVersion(expected: Int, actual: Int)
    case host(String)
    case malformedResponse
    case processExited(Int32)
}

public struct HelloRequest: Codable, Sendable {
    public let id: String
    public let type: String
    public let protocolVersion: Int

    public init(id: String = UUID().uuidString) {
        self.id = id
        self.type = "hello"
        self.protocolVersion = NativeProtocol.version
    }
}

public struct HelloResponse: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let protocolVersion: Int
    public let appVersion: String
    public let capabilities: [String]
}

public struct UnaryRequest<Payload: Encodable & Sendable>: Encodable, Sendable {
    public let id: String
    public let type: String
    public let method: String
    public let payload: Payload

    public init(id: String = UUID().uuidString, method: String, payload: Payload) {
        self.id = id
        self.type = "request"
        self.method = method
        self.payload = payload
    }
}

public struct EmptyPayload: Codable, Equatable, Sendable {
    public init() {}
}

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}

public struct NativeEventFrame: Decodable, Sendable {
    public let type: String
    public let stream: String
    public let value: ServerRequest
}

public struct NativeRespondRequest<Result: Encodable & Sendable>: Encodable, Sendable {
    public let id: String
    public let type: String
    public let rpcId: String
    public let result: Result

    public init(id: String = UUID().uuidString, rpcId: String, result: Result) {
        self.id = id
        self.type = "respond"
        self.rpcId = rpcId
        self.result = result
    }
}

public struct ClientSuccess<Value: Encodable & Sendable>: Encodable, Sendable {
    public let ok = true
    public let value: Value

    public init(value: Value) {
        self.value = value
    }
}

public struct ClientFailure: Encodable, Sendable {
    public struct Failure: Encodable, Sendable {
        public let code: String
        public let message: String
        public let details: JSONValue
    }

    public let ok = false
    public let error: Failure

    public init(code: String, message: String, details: JSONValue = .object([:])) {
        self.error = Failure(code: code, message: message, details: details)
    }
}

public struct RpcReceipt: Decodable, Sendable {
    public let accepted: Bool
    public let reason: String?
}

public struct ServerRequest: Decodable, Sendable {
    public let type: String
    public let rpcId: String
    public let method: String
    public let payload: JSONValue
}

public struct ShutdownRequest: Codable, Sendable {
    public let id: String
    public let type: String

    public init(id: String = UUID().uuidString) {
        self.id = id
        self.type = "shutdown"
    }
}

public struct TransportFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
}

public struct TransportResponse<Value: Decodable & Sendable>: Decodable, Sendable {
    public let id: String
    public let type: String
    public let value: Value?
    public let error: TransportFailure?
}

public struct ServerResponse<Value: Decodable & Sendable>: Decodable, Sendable {
    public let type: String
    public let rpcId: String
    public let result: RpcResult<Value>
}

public enum RpcResult<Value: Decodable & Sendable>: Decodable, Sendable {
    case success(Value)
    case failure(code: String, message: String)

    private enum CodingKeys: String, CodingKey {
        case ok
        case value
        case error
    }

    private struct Failure: Decodable {
        let code: String
        let message: String
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .ok) {
            self = .success(try container.decode(Value.self, forKey: .value))
        } else {
            let failure = try container.decode(Failure.self, forKey: .error)
            self = .failure(code: failure.code, message: failure.message)
        }
    }
}
