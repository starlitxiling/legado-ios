import XCTest
@testable import LegadoCore

final class LocalizedErrorTests: XCTestCase {
    func testHTTPFailureOmitsCredentialsQueryAndFragment() {
        let message = WebBookError.httpStatus(503, "https://user:secret@example.test/book?token=private#fragment").localizedDescription
        XCTAssertTrue(message.contains("example.test/book"))
        for secret in ["user", "secret", "token", "private", "fragment"] { XCTAssertFalse(message.contains(secret)) }
    }

    func testCoreErrorsExplainFailureAndRecovery() {
        let cases: [(Error, String)] = [
            (WebBookError.missingRule("ruleContent"), "ruleContent"),
            (WebDavError.httpStatus(401), "账号"),
            (StorageError.chapterBookMismatch, "章节"),
            (BackupArchiveError.checksum("books.json"), "books.json"),
            (BackupAESError.cryptFailed(-1), "解密"),
            (BackupError.passwordRequired(file: "config.json"), "config.json"),
            (BookProgressSyncError.identityMismatch, "进度"),
            (RuleSubImportError.unsupportedType(9), "9"),
            (HttpTTSSource.SynthesisError.invalidResponse(503), "503"),
            (WebHttpError.tooLarge, "过大"),
            (WebSocketError.invalidUTF8, "编码"),
            (CustomUrl.AttributeError.invalidValue("serverID"), "serverID"),
            (UrlOptions.OptionError.invalidJSON, "JSON"),
            (AnalyzeByJSoup.EvaluationError.invalidIndex, "索引"),
            (RuleEvaluationError.unmatchedCapture(3), "3"),
            (BookshelfEditError.emptyName, "名称"),
            (ReadDurationError.overflow, "时长"),
            (RuleAnalyzer.AnalysisError.unbalanced(position: 12), "12"),
            (AnalyzeByXPath.EvaluationError.invalidXPath("//["), "//["),
            (RssError.httpStatus(404), "404"),
            (JsonPathError.invalidPath("$.bad"), "$.bad"),
            (HeadlessWebViewError.timedOut, "超时"),
            (ImageDownloadError.emptyImage, "图片"),
            (ReplayHttpClient.ReplayError.unmatched(method: "GET", url: URL(string: "https://fixture.test")!), "fixture.test"),
            (ContentHelpError.invalidParagraphRange(2, 8, 4), "段落"),
            (ContentProcessorError.regexTimeout(42), "42"),
            (BookExporter.ExportError.missingImage("cover.png"), "cover.png"),
            (UrlRequestBuilder.RequestError.invalidURL("bad-url"), "bad-url"),
            (ResponseDecoder.DecodingError.unsupportedCharset("bad-charset"), "bad-charset"),
            (BookshelfRefresh.UpdateError.missingSource, "书源"),
            (HttpProxy.ConfigurationError.invalidProxy, "代理"),
            (ChineseConverterError.missingDictionary("dictionary"), "dictionary"),
            (LocalBookError.invalidFilenameScript, "文件名"),
            (BookArchiveError.missing("body.txt"), "body.txt"),
            (UmdError.invalid("header"), "UMD"),
            (PdfFileError.locked, "解密"),
            (MobiError.invalid("header"), "MOBI"),
            (SourceReplacementError.invalidBookSource, "书源"),
            (DictRuleValidationError.missingRequiredFields, "字典"),
            (SourceLoginError.rejected, "登录"),
            (JsEngineError.unavailable, "脚本"),
            (JsEngineError.exception("Unsupported cipher mode: AES/XTS"), "书源脚本执行出错：不支持的（cipher mode: AES/XTS）"),
            (JsEngineError.exception("TypeError: x is undefined"), "TypeError: x is undefined"),
            (JsEngineError.exception("Error: JavaScript: Invalid hexadecimal input"), "书源脚本执行出错：无效的（hexadecimal input）"),
            (NetworkRoutingError.invalidAddress("host.test"), "host.test"),
            (MultipartBody.EncodingError.invalidFilePart("file"), "file"),
            (HighlightRuleDecodingError(description: "rules.json"), "rules.json"),
            (ReaderThemeImportError(issues: ["textSize"]), "textSize")
        ]
        for (error, expected) in cases {
            let localized = error as? LocalizedError
            let message = localized?.errorDescription ?? ""
            XCTAssertTrue(message.contains(expected), "\(error): \(message)")
            XCTAssertTrue(message.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(error): \(message)")
            XCTAssertFalse((localized?.recoverySuggestion ?? "").isEmpty, "\(error)")
            XCTAssertFalse(message.contains("couldn’t be completed"))
            XCTAssertFalse(message.contains("The data couldn’t be read"))
        }
    }

    func testWebDavAuthenticationAndMissingPathHaveDifferentRecovery() {
        XCTAssertNotEqual((WebDavError.httpStatus(401) as Error).localizedDescription,
                          (WebDavError.httpStatus(404) as Error).localizedDescription)
        XCTAssertTrue((WebDavError.httpStatus(403) as Error).localizedDescription.contains("权限"))
    }
}
