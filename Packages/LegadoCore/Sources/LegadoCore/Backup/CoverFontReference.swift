import Foundation

public enum CoverFontReference: Equatable, Sendable {
    case none
    case name(String)
    case file(URL)

    public init(_ value: String) {
        guard !value.isEmpty else { self = .none; return }
        if let url = URL(string: value), url.isFileURL {
            self = .file(url)
        } else if value.contains("/") || ["ttf", "otf", "ttc"].contains((value as NSString).pathExtension.lowercased()) {
            self = .file(URL(fileURLWithPath: value))
        } else {
            self = .name(value)
        }
    }
}
