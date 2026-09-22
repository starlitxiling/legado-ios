import Foundation

extension WebBookError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingRule(let rule): return "书源缺少规则：\(rule)"
        case .emptyToc: return "书源没有返回目录。"
        case .emptyContent: return "书源没有返回正文。"
        case .bookNotFound(let name, let author): return "未找到书籍：\(name) / \(author)"
        case .emptyDownloadURLs: return "书源没有返回下载地址。"
        case .httpStatus(let status, let url): return "书源请求失败（HTTP \(status)）：\(url)"
        case .unsupported(let feature): return "书源使用了尚不支持的功能：\(feature)"
        }
    }
    public var recoverySuggestion: String? { "请重试、切换书源，或在书源管理中检查规则与登录状态。" }
}

extension WebDavError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "WebDAV 地址无效。"
        case .foreignOrigin: return "WebDAV 文件地址不属于配置的服务器。"
        case .httpStatus(401): return "WebDAV 账号或密码不正确。"
        case .httpStatus(403): return "WebDAV 账号没有访问此路径的权限。"
        case .httpStatus(404): return "WebDAV 路径或文件不存在。"
        case .httpStatus(let code): return "WebDAV 请求失败（HTTP \(code)）。"
        case .invalidXML: return "WebDAV 返回的文件列表格式不正确。"
        case .responseTooLarge: return "WebDAV 响应超过允许的大小。"
        case .responseLimitUnavailable: return "当前网络客户端无法限制 WebDAV 响应大小。"
        case .missingServerID: return "WebDAV 文件缺少服务器编号。"
        case .invalidServer(let id): return "找不到 WebDAV 服务器配置：\(id)"
        }
    }
    public var recoverySuggestion: String? {
        switch self {
        case .httpStatus(401), .httpStatus(403): return "请在备份与恢复中检查账号、密码和路径权限。"
        case .httpStatus(404): return "请检查远程目录和文件名，刷新文件列表后重试。"
        default: return "请检查 WebDAV 服务器地址与配置，再重试。"
        }
    }
}

extension BackupArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidArchive: return "备份压缩包已损坏或内容不完整。"
        case .unsupportedFormat: return "备份压缩格式不受支持。"
        case .unsafePath(let path): return "备份中存在不安全的文件路径：\(path)"
        case .duplicatePath(let path): return "备份中存在重复的文件路径：\(path)"
        case .sizeLimit: return "备份超过允许的大小或文件数量。"
        case .checksum(let path): return "备份文件校验失败：\(path)"
        }
    }
    public var recoverySuggestion: String? { "请重新下载或导出完整备份，再尝试恢复。" }
}

extension BackupAESError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCiphertext: return "备份加密数据格式不正确。"
        case .invalidUTF8: return "备份解密后的文字编码无效。"
        case .cryptFailed(let code): return "备份解密失败（错误码 \(code)）。"
        }
    }
    public var recoverySuggestion: String? { "请检查备份的本地密码，并确认文件完整。" }
}

extension BackupError: LocalizedError {
    public var errorDescription: String? {
        switch self { case .passwordRequired(let file): return "恢复 \(file) 需要备份的本地密码。" }
    }
    public var recoverySuggestion: String? { "请输入制作该备份时设置的本地密码，再恢复。" }
}

extension BookProgressSyncError: LocalizedError {
    public var errorDescription: String? { "远程阅读进度与当前书籍不匹配。" }
    public var recoverySuggestion: String? { "请检查远程进度对应的书名和作者，确认后重新同步。" }
}

extension HighlightRuleDecodingError: LocalizedError {
    var errorDescription: String? { "高亮规则数据格式不正确：" + description }
    var recoverySuggestion: String? { "请检查高亮规则备份文件，或重新导出后恢复。" }
}

extension RuleSubImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRules: return "订阅返回的规则格式不正确。"
        case .invalidURL: return "规则订阅地址无效。"
        case .httpStatus(let code): return "规则订阅请求失败（HTTP \(code)）。"
        case .unsupportedType(let type): return "不支持此规则订阅类型：\(type)"
        case .unsupportedScript: return "规则订阅脚本不受支持。"
        }
    }
    public var recoverySuggestion: String? { "请检查订阅地址、类型及内容，再重新导入。" }
}

extension HttpTTSSource.SynthesisError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let code): return "朗读引擎请求失败（HTTP \(code)）。"
        case .invalidContentType(let type): return "朗读引擎返回了非音频内容：\(type)"
        case .emptyAudio: return "朗读引擎返回的音频为空。"
        }
    }
    public var recoverySuggestion: String? { "请检查朗读引擎的地址与凭据，或切换到系统朗读。" }
}

extension WebHttpError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformed: return "Web 服务收到的请求格式不正确。"
        case .tooLarge: return "Web 服务收到的请求过大。"
        case .unsupportedEncoding: return "Web 服务不支持此请求编码。"
        }
    }
    public var recoverySuggestion: String? { "请检查调用方的请求格式和内容大小，再重试。" }
}

extension WebSocketError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .protocolError: return "实时连接收到不符合协议的数据。"
        case .invalidUTF8: return "实时连接收到的文字编码无效。"
        case .tooLarge: return "实时连接收到的数据过大。"
        }
    }
    public var recoverySuggestion: String? { "请重新连接，并检查客户端发送的数据。" }
}

extension CustomUrl.AttributeError: LocalizedError {
    public var errorDescription: String? {
        switch self { case .invalidValue(let value): return "链接附加参数无效：\(value)" }
    }
    public var recoverySuggestion: String? { "请检查链接后附加参数的格式。" }
}

extension UrlOptions.OptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "请求参数不是有效的 JSON。"
        case .illegalArgument: return "请求参数的值或类型不正确。"
        }
    }
    public var recoverySuggestion: String? { "请在书源管理中检查请求地址后的参数。" }
}

extension AnalyzeByJSoup.EvaluationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingContent: return "网页解析缺少内容。"
        case .invalidIndex: return "网页规则的索引无效。"
        case .missingSelectorArgument: return "网页选择器缺少参数。"
        case .missingCSSKeyword: return "网页规则缺少 CSS 选择器。"
        }
    }
    public var recoverySuggestion: String? { "请检查书源的网页解析规则，或切换书源。" }
}

extension BookshelfEditError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidGroup: return "书架分组无效或已被删除。"
        case .groupLimit: return "书架分组已达到数量上限。"
        case .emptyName: return "分组名称不能为空。"
        case .missingBook: return "书籍已不在书架中。"
        }
    }
    public var recoverySuggestion: String? { "请刷新书架，检查分组名称与数量后重试。" }
}

extension StorageError: LocalizedError {
    public var errorDescription: String? { "章节所属书籍与保存目标不一致。" }
    public var recoverySuggestion: String? { "请重新打开书籍并刷新目录，再重试。" }
}

extension ReadDurationError: LocalizedError {
    public var errorDescription: String? { "阅读时长超出允许的数值范围。" }
    public var recoverySuggestion: String? { "请检查导入的阅读记录，移除异常记录后重试。" }
}

extension RuleAnalyzer.AnalysisError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .exhausted: return "规则内容不完整。"
        case .invalidDelimiter: return "规则分隔符无效。"
        case .unbalanced(let position): return "规则括号或引号未闭合，位置：\(position)"
        }
    }
    public var recoverySuggestion: String? { "请检查书源规则中的分隔符、引号与括号。" }
}

extension AnalyzeByXPath.EvaluationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidXPath(let rule): return "XPath 规则无效：\(rule)"
        case .unsupportedExtension(let name): return "XPath 扩展不受支持：\(name)"
        }
    }
    public var recoverySuggestion: String? { "请修改书源的 XPath 规则，或切换书源。" }
}

extension RssError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidXML: return "订阅内容不是有效的 XML。"
        case .invalidSource: return "订阅源配置无效。"
        case .invalidURL: return "订阅地址无效。"
        case .httpStatus(let code): return "订阅请求失败（HTTP \(code)）。"
        case .paginationLimit: return "订阅翻页已达到上限。"
        }
    }
    public var recoverySuggestion: String? { "请检查订阅源地址与解析规则，再刷新。" }
}

extension JsonPathError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): return "JSON 路径无效：\(path)"
        case .pathNotFound: return "JSON 内容中找不到规则指定的字段。"
        case .invalidFunction(let function): return "JSON 路径函数无效：\(function)"
        }
    }
    public var recoverySuggestion: String? { "请检查书源的 JSON 路径规则与服务器返回内容。" }
}

extension HeadlessWebViewError: LocalizedError {
    public var errorDescription: String? { description }
    public var recoverySuggestion: String? {
        switch self {
        case .notForeground: return "请回到应用前台后重试。"
        case .interactionBusy: return "请先完成当前登录或验证，再重试。"
        default: return "请重试网页加载，或切换书源。"
        }
    }
}

extension ImageDownloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDecodeResult: return "图片解码结果无效。"
        case .emptyImage: return "下载的图片为空。"
        }
    }
    public var recoverySuggestion: String? { "请重试图片加载，并检查书源的图片解码规则。" }
}

extension ReplayHttpClient.ReplayError: LocalizedError {
    public var errorDescription: String? {
        switch self { case .unmatched(let method, let url): return "测试响应未配置：\(method) \(url.absoluteString)" }
    }
    public var recoverySuggestion: String? { "请补充对应请求的测试响应。" }
}

extension ContentHelpError: LocalizedError {
    public var errorDescription: String? {
        switch self { case .invalidParagraphRange(let start, let end, let count): return "段落范围无效：\(start)...\(end)，共有 \(count) 段。" }
    }
    public var recoverySuggestion: String? { "请重新加载正文后再选择段落。" }
}

extension ContentProcessorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRule(let id): return "正文替换规则无效，规则编号：\(id)"
        case .regexTimeout(let id): return "正文替换规则执行超时，规则编号：\(id)"
        }
    }
    public var recoverySuggestion: String? { "请修改或停用该替换规则，再重新加载正文。" }
}

extension BookExporter.ExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRange: return "导出章节范围无效。"
        case .unsupportedCover: return "封面图片格式不受支持。"
        case .archiveTooLarge: return "导出文件超过允许的大小。"
        case .missingImage(let name): return "导出缺少图片：\(name)"
        }
    }
    public var recoverySuggestion: String? { "请检查章节范围，补充缓存或减少导出内容后重试。" }
}

extension UrlRequestBuilder.RequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "请求地址无效：\(url)"
        case .invalidHeaders: return "请求头格式不正确。"
        case .webViewNotImplemented: return "当前请求需要网页加载服务。"
        case .unencodable(let value): return "请求内容无法按指定编码转换：\(value)"
        }
    }
    public var recoverySuggestion: String? { "请在书源管理中检查请求地址、请求头与编码。" }
}

extension ResponseDecoder.DecodingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedCharset(let charset): return "不支持此文字编码：\(charset)"
        case .invalidBytes(let charset): return "响应内容无法按 \(charset) 编码读取。"
        }
    }
    public var recoverySuggestion: String? { "请检查书源设置的字符编码，或改为自动识别。" }
}

extension HttpProxy.ConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidProxy: return "代理服务器配置无效。"
        case .unsupportedSocks4Authentication: return "不支持 SOCKS4 账号认证。"
        }
    }
    public var recoverySuggestion: String? { "请检查代理地址和认证方式，或关闭代理后重试。" }
}

extension ChineseConverterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingDictionary(let name): return "繁简转换词典缺失：\(name)"
        case .invalidDictionary(let name, let line): return "繁简转换词典 \(name) 第 \(line) 行格式不正确。"
        }
    }
    public var recoverySuggestion: String? { "请重新安装完整应用资源，或暂时关闭繁简转换。" }
}

extension LocalBookError {
    public var recoverySuggestion: String? { "请检查文件完整性、格式与编码，再重新导入。" }
}
extension BookArchiveError {
    public var recoverySuggestion: String? { "请重新获取完整且未损坏的电子书文件，再导入。" }
}
extension UmdError {
    public var recoverySuggestion: String? { "请重新获取完整的 UMD 文件后导入。" }
}
extension PdfFileError {
    public var recoverySuggestion: String? { "请检查 PDF 是否完整、是否需要解密，再导入。" }
}
extension MobiError {
    public var recoverySuggestion: String? { "请检查 MOBI 文件完整性，或转换为 EPUB 后导入。" }
}
extension SourceReplacementError {
    public var recoverySuggestion: String? { "请在书源替换规则中检查对应表达式，或关闭导入净化。" }
}
extension DictRuleValidationError {
    public var recoverySuggestion: String? { "请补齐字典规则的名称、地址等必填字段。" }
}
extension SourceLoginError {
    public var recoverySuggestion: String? { "请检查账号与书源登录脚本，重新登录后再验证。" }
}
extension JsEngineError {
    public var recoverySuggestion: String? { "请检查书源脚本和报错位置，或切换书源。" }
}
extension NetworkRoutingError {
    public var recoverySuggestion: String? { "请检查自定义主机映射中的域名与 IP 地址。" }
}
extension MultipartBody.EncodingError {
    var recoverySuggestion: String? { "请检查上传表单、文件字段及内容类型。" }
}
extension BookshelfRefresh.UpdateError {
    public var recoverySuggestion: String? { "请导入对应书源，或为书籍切换书源后刷新目录。" }
}
