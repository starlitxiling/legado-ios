import GRDB

/// 时间戳由调用方提供，默认 0；JSON 复合字段保存 Room 转换后的文本。
public protocol StorageRow: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {}
