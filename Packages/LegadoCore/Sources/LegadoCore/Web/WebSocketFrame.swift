import Foundation

public enum WebSocketError: Error, Equatable {
    case protocolError, invalidUTF8, tooLarge
    public var closeCode: UInt16 {
        switch self { case .protocolError: return 1002; case .invalidUTF8: return 1007; case .tooLarge: return 1009 }
    }
}

public struct WebSocketFrame: Equatable, Sendable {
    public enum Opcode: UInt8, Sendable { case continuation = 0, text = 1, binary = 2, close = 8, ping = 9, pong = 10 }
    public let opcode: Opcode
    public let payload: Data
    public let final: Bool

    public init(opcode: Opcode, payload: Data = Data(), final: Bool = true) {
        self.opcode = opcode; self.payload = payload; self.final = final
    }

    public func encoded(mask: [UInt8]? = nil) -> Data {
        precondition(mask == nil || mask?.count == 4)
        var bytes = Data([opcode.rawValue | (final ? 0x80 : 0)])
        let flag: UInt8 = mask == nil ? 0 : 0x80
        if payload.count < 126 { bytes.append(flag | UInt8(payload.count)) }
        else if payload.count <= 65535 {
            bytes.append(flag | 126)
            bytes.append(UInt8(payload.count >> 8)); bytes.append(UInt8(payload.count & 255))
        } else {
            bytes.append(flag | 127)
            for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((UInt64(payload.count) >> shift) & 255)) }
        }
        if let mask {
            bytes.append(contentsOf: mask)
            bytes.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        } else { bytes.append(payload) }
        return bytes
    }

    public static func close(code: UInt16, reason: String) -> WebSocketFrame {
        var text = reason
        while text.utf8.count > 123 { text.removeLast() }
        return .init(opcode: .close, payload: Data([UInt8(code >> 8), UInt8(code & 255)]) + Data(text.utf8))
    }
}

public struct WebSocketFrameDecoder {
    private var buffer = Data()
    private var fragment = Data()
    private var fragmentOpcode: WebSocketFrame.Opcode?
    private var failed = false
    private let requireMask: Bool
    private let maximumMessageSize: Int

    public init(requireMask: Bool = true, maximumMessageSize: Int = 4 * 1024 * 1024) {
        self.requireMask = requireMask; self.maximumMessageSize = maximumMessageSize
    }

    public mutating func append(_ data: Data) throws -> [WebSocketFrame] {
        guard !failed else { return [] }
        do { return try decode(data) }
        catch {
            failed = true
            buffer.removeAll(); fragment.removeAll(); fragmentOpcode = nil
            throw error
        }
    }

    private mutating func decode(_ data: Data) throws -> [WebSocketFrame] {
        buffer.append(data)
        var output: [WebSocketFrame] = []
        while buffer.count >= 2 {
            let bytes = [UInt8](buffer.prefix(14))
            let final = bytes[0] & 0x80 != 0, masked = bytes[1] & 0x80 != 0
            guard bytes[0] & 0x70 == 0, let opcode = WebSocketFrame.Opcode(rawValue: bytes[0] & 15),
                  masked == requireMask else { throw WebSocketError.protocolError }
            let control = opcode.rawValue >= 8
            let marker = bytes[1] & 127
            guard !control || (final && marker <= 125) else { throw WebSocketError.protocolError }
            var length = UInt64(marker), offset = 2
            if marker == 126 || marker == 127 {
                let count = marker == 126 ? 2 : 8
                guard buffer.count >= 2 + count else { break }
                if count == 8 && bytes[2] & 0x80 != 0 { throw WebSocketError.protocolError }
                length = 0
                for byte in bytes[2..<(2 + count)] { length = (length << 8) | UInt64(byte) }
                guard length >= (count == 2 ? 126 : 65536) else { throw WebSocketError.protocolError }
                offset += count
            }
            guard length <= UInt64(maximumMessageSize) else { throw WebSocketError.tooLarge }
            let maskOffset = offset
            if masked { offset += 4 }
            guard buffer.count >= offset + Int(length) else { break }
            var payload = Data(buffer.dropFirst(offset).prefix(Int(length)))
            if masked {
                let mask = bytes[maskOffset..<(maskOffset + 4)]
                for index in 0..<payload.count { payload[index] ^= mask[maskOffset + index % 4] }
            }
            buffer = Data(buffer.dropFirst(offset + Int(length)))
            if control {
                if opcode == .close { try Self.validateClose(payload) }
                output.append(.init(opcode: opcode, payload: payload))
                if opcode == .close { buffer.removeAll(); fragment.removeAll(); fragmentOpcode = nil; break }
                continue
            }
            if opcode == .continuation {
                guard fragmentOpcode != nil else { throw WebSocketError.protocolError }
            } else {
                guard fragmentOpcode == nil else { throw WebSocketError.protocolError }
                fragmentOpcode = opcode
            }
            guard fragment.count + payload.count <= maximumMessageSize else { throw WebSocketError.tooLarge }
            fragment.append(payload)
            if final, let type = fragmentOpcode {
                if type == .text && String(data: fragment, encoding: .utf8) == nil { throw WebSocketError.invalidUTF8 }
                output.append(.init(opcode: type, payload: fragment))
                fragment.removeAll(keepingCapacity: false); fragmentOpcode = nil
            }
        }
        return output
    }

    private static func validateClose(_ payload: Data) throws {
        if payload.isEmpty { return }
        guard payload.count >= 2 else { throw WebSocketError.protocolError }
        let code = UInt16(payload[0]) << 8 | UInt16(payload[1])
        guard (1000...1014).contains(code) && ![1004, 1005, 1006].contains(code) || (3000...4999).contains(code) else {
            throw WebSocketError.protocolError
        }
        guard String(data: payload.dropFirst(2), encoding: .utf8) != nil else { throw WebSocketError.invalidUTF8 }
    }
}

public struct WebSocketCloseState {
    public private(set) var sent = false
    public private(set) var received = false
    public init() {}
    public mutating func initiate(code: UInt16, reason: String) -> WebSocketFrame? {
        guard !sent else { return nil }
        sent = true
        return .close(code: code, reason: reason)
    }
    public mutating func receive(_ frame: WebSocketFrame) -> WebSocketFrame? {
        guard frame.opcode == .close else { return nil }
        received = true
        guard !sent else { return nil }
        sent = true
        return frame
    }
}
