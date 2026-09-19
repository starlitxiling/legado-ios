import Foundation

public struct WebBookConfiguration {
    public var cacheDirectory: URL?
    public var threadCount: Int
    public var adaptSpecialStyle: Bool
    public var headlessWebView: (any HeadlessWebViewProtocol)?

    public init(cacheDirectory: URL? = nil, threadCount: Int = 32, adaptSpecialStyle: Bool = true,
                headlessWebView: (any HeadlessWebViewProtocol)? = nil) {
        self.cacheDirectory = cacheDirectory
        self.threadCount = max(1, min(128, threadCount))
        self.adaptSpecialStyle = adaptSpecialStyle
        self.headlessWebView = headlessWebView
    }
}
