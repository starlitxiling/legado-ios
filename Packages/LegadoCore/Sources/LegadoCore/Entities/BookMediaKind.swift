import Foundation

public enum BookMediaKind: Equatable, Sendable {
    case text, audio, image, video, file

    public init(type: Int) {
        if type & 4 != 0 { self = .video }
        else if type & 128 != 0 { self = .file }
        else if type & 32 != 0 { self = .audio }
        else if type & 64 != 0 { self = .image }
        else { self = .text }
    }
}

extension Book {
    public var isAudio: Bool { type & 32 != 0 }
    public var isImage: Bool { type & 64 != 0 }
    public var isVideo: Bool { type & 4 != 0 }
    public var isWebFile: Bool { type & 128 != 0 }
    public var mediaKind: BookMediaKind { BookMediaKind(type: type) }
}

extension BookSource {
    public var mediaBookType: Int {
        switch bookSourceType {
        case 1: return 32
        case 2: return 64
        case 3: return 136
        case 4: return 4
        default: return 8
        }
    }
}
