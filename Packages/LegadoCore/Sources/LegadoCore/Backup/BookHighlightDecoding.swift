import Foundation
import GRDB

extension BookHighlight {
    static func restoredStyle(fill: Int = 0, textColor: Int = 0) -> String {
        "{\"fill\":\(fill),\"textColor\":\(textColor),\"bold\":false,\"italic\":false,\"fontPath\":\"\"}"
    }
    public init(row: Row) {
        self.init()
        time = row["time"]
        bookUrl = row["bookUrl"]
        chapterUrl = row["chapterUrl"]
        bookName = row["bookName"]
        bookAuthor = row["bookAuthor"]
        chapterIndex = row["chapterIndex"]
        chapterPos = row["chapterPos"]
        chapterPosEnd = row["chapterPosEnd"]
        layoutTitleLength = row["layoutTitleLength"]
        chapterName = row["chapterName"]
        bookText = row["bookText"]
        style = row["style"]
        note = row["note"]
    }

    private enum BackupCodingKeys: String, CodingKey {
        case time, bookUrl, chapterUrl, bookName, bookAuthor, chapterIndex, chapterPos, chapterPosEnd, layoutTitleLength, chapterName, bookText, style, note
        case bgColor, textColor
    }

    public init(from decoder: Decoder) throws {
        self.init()
        time = GsonDecoding.time(from: decoder)
        let container = try decoder.container(keyedBy: BackupCodingKeys.self)
        time = try container.gsonLong(forKey: .time) ?? time
        bookUrl = try container.gsonString(forKey: .bookUrl) ?? bookUrl
        chapterUrl = try container.gsonString(forKey: .chapterUrl) ?? chapterUrl
        bookName = try container.gsonString(forKey: .bookName) ?? bookName
        bookAuthor = try container.gsonString(forKey: .bookAuthor) ?? bookAuthor
        chapterIndex = try container.gsonInt(forKey: .chapterIndex) ?? chapterIndex
        chapterPos = try container.gsonInt(forKey: .chapterPos) ?? chapterPos
        chapterPosEnd = try container.gsonInt(forKey: .chapterPosEnd) ?? chapterPosEnd
        layoutTitleLength = try container.gsonInt(forKey: .layoutTitleLength) ?? layoutTitleLength
        chapterName = try container.gsonString(forKey: .chapterName) ?? chapterName
        bookText = try container.gsonString(forKey: .bookText) ?? bookText
        style = try container.gsonString(forKey: .style) ?? style
        note = try container.gsonString(forKey: .note) ?? note
        if style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            func color(_ key: BackupCodingKeys) throws -> Int {
                guard case let .number(raw)? = try container.decodeIfPresent(GsonValue.self, forKey: key),
                      let value = Double(raw), value.isFinite else { return 0 }
                if value >= Double(Int32.max) { return Int(Int32.max) }
                if value <= Double(Int32.min) { return Int(Int32.min) }
                return Int(value)
            }
            let fill = try color(.bgColor), text = try color(.textColor)
            if fill != 0 || text != 0 { style = Self.restoredStyle(fill: fill, textColor: text) }
        }
    }
}
