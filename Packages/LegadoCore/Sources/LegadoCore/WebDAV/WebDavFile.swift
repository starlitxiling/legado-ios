import Foundation

public struct WebDavFile: Sendable, Equatable {
    public let url: URL
    public let displayName: String
    public let size: Int64
    public let isDirectory: Bool
    public let lastModified: Date?

    public init(url: URL, displayName: String, size: Int64 = 0, isDirectory: Bool = false, lastModified: Date? = nil) {
        self.url = url
        self.displayName = displayName
        self.size = size
        self.isDirectory = isDirectory
        self.lastModified = lastModified
    }
}
