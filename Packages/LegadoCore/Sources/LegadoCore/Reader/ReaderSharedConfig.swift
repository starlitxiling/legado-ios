import Foundation

public struct ReaderSharedConfig: Codable, Equatable, Sendable {
    public var autoReadSpeed = 10
    public var readStyleSelect = 0
    public var comicStyleSelect = 0
    public var shareLayout = false
    public var hideStatusBar = false
    public var hideNavigationBar = false
    public var useZhLayout = false
    public var readBodyToLh = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case autoReadSpeed, readStyleSelect, comicStyleSelect, shareLayout, hideStatusBar, hideNavigationBar, useZhLayout, readBodyToLh
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        autoReadSpeed = try values.decodeIfPresent(Int.self, forKey: .autoReadSpeed) ?? autoReadSpeed
        readStyleSelect = try values.decodeIfPresent(Int.self, forKey: .readStyleSelect) ?? readStyleSelect
        comicStyleSelect = try values.decodeIfPresent(Int.self, forKey: .comicStyleSelect) ?? readStyleSelect
        shareLayout = try values.decodeIfPresent(Bool.self, forKey: .shareLayout) ?? shareLayout
        hideStatusBar = try values.decodeIfPresent(Bool.self, forKey: .hideStatusBar) ?? hideStatusBar
        hideNavigationBar = try values.decodeIfPresent(Bool.self, forKey: .hideNavigationBar) ?? hideNavigationBar
        useZhLayout = try values.decodeIfPresent(Bool.self, forKey: .useZhLayout) ?? useZhLayout
        readBodyToLh = try values.decodeIfPresent(Bool.self, forKey: .readBodyToLh) ?? readBodyToLh
    }
}

public struct ReaderThemes: Codable, Equatable, Sendable {
    public var configList: [ReadBookConfig] = []
    public var shareConfig = ReadBookConfig()
    public var shared = ReaderSharedConfig()
    public init() {}

    public func current(isComic: Bool = false) -> ReadBookConfig {
        if shared.shareLayout { return shareConfig }
        let index = isComic ? shared.comicStyleSelect : shared.readStyleSelect
        return configList.indices.contains(index) ? configList[index] : ReadBookConfig()
    }
}
