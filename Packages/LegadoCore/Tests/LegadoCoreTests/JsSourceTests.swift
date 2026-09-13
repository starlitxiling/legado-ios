import XCTest
@testable import LegadoCore

final class JsSourceTests: XCTestCase {
    private let script = """
    var config = {bookSourceName:'合成源',bookSourceUrl:'https://example.invalid',
                  exploreUrl:[{title:'分类',url:'fiction'}]};
    function search(key,page) { return [{name:key,author:'作者',bookUrl:baseUrl+'/book',kind:''}]; }
    function explore(url,page) { return search(url,page); }
    function getBookInfo(book) { return {name:'新名称',intro:'简介',tocUrl:baseUrl+'/toc/'}; }
    function getChapters(book) { return [{title:'第一章',url:'1'},{title:'第二章',url:'2'}]; }
    function getContent(chapter,book,nextChapterUrl) { return book.name+'正文'; }
    """

    func testImportedJourney() async throws {
        guard case .sources(let sources) = SourceImporter().parseBookSources(script) else {
            return XCTFail("纯 JS 应导入为书源")
        }
        XCTAssertEqual(sources.first?.support, .supported)
        let web = WebBook(source: try XCTUnwrap(sources.first?.source), client: ReplayHttpClient(), now: { 123 })
        let results = try await web.search(key: "测试", page: 2)
        XCTAssertEqual(results.map(\.name), ["测试"])
        XCTAssertEqual(results.first?.origin, "https://example.invalid")
        var book = try await web.bookInfo(try XCTUnwrap(results.first))
        XCTAssertEqual(book.name, "测试")
        XCTAssertEqual(book.intro, "简介")
        let chapters = try await web.chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.url), ["https://example.invalid/toc/1", "https://example.invalid/toc/2"])
        XCTAssertEqual(book.totalChapterNum, 2)
        let content = try await web.content(book: book, chapter: chapters[0], includeTitle: false)
        XCTAssertEqual(content.rawContent, "测试正文")
        let explored = try await web.explore(url: "fiction")
        XCTAssertEqual(explored.first?.name, "fiction")
    }

    func testJSONMainJsSupported() throws {
        var source = BookSource()
        source.bookSourceUrl = "https://example.invalid"; source.mainJs = script
        let text = String(decoding: try JSONEncoder().encode(source), as: UTF8.self)
        guard case .sources(let sources) = SourceImporter().parseBookSources(text) else { return XCTFail("JSON 解析失败") }
        XCTAssertEqual(sources.first?.support, .supported)
    }

    func testConfigFormsAndPriority() throws {
        for declaration in ["var config", "let config", "const config", "var source"] {
            let source = try JsSourceConfig.extract("// 注释不会代替配置\n" + script.replacingOccurrences(of: "var config", with: declaration))
            XCTAssertEqual(source.bookSourceName, "合成源")
            XCTAssertTrue(source.exploreUrl?.contains("分类") == true)
            XCTAssertNotNil(source.mainJs)
        }
        let legacy = try JsSourceConfig.extract(script.replacingOccurrences(of: "var config", with: "var source") + "\nvar config={};")
        XCTAssertEqual(legacy.bookSourceName, "合成源")
        let preferred = try JsSourceConfig.extract(script + "\nvar source={bookSourceUrl:'legacy',bookSourceName:'旧版'};")
        XCTAssertEqual(preferred.bookSourceName, "合成源")
    }

    func testConfigRejectsMissingFunctionsAndInvalidDeclarations() {
        for text in ["// @name 注释源\nfunction search() {}", "var config={};",
                     script.replacingOccurrences(of: "function getContent", with: "function other"),
                     script.replacingOccurrences(of: "function explore", with: "function other"),
                     script + "\nconfig.maxBatchSize=2;",
                     script + "\nfunction getReviewSummary() {}",
                     script + "\nthrow new Error('故障');"] {
            XCTAssertThrowsError(try JsSourceConfig.extract(text))
        }
    }

    func testNormalizationAndStripping() throws {
        let source = try JsSourceConfig.extract(script + """

        config.ruleSearch={name:'h1'}; config.loginUi=[];
        config.maxBatchSize=99; function getContentBatch() {}
        """)
        XCTAssertNil(source.ruleSearch)
        XCTAssertNil(source.loginUi)
        XCTAssertEqual(source.ruleContent?.maxBatchSize, 50)
        let file = try JsSourceConfig.extract("""
        var config={bookSourceName:'文件',bookSourceUrl:'https://example.invalid',bookSourceType:3};
        function search() {} function getBookInfo() {}
        """)
        XCTAssertEqual(file.bookSourceType, 3)
    }

    func testOptionalRequiredErrorsAndFreshScope() throws {
        var source = try JsSourceConfig.extract(script)
        source.mainJs = """
        var counter=0;
        function increment(){return ++counter;}
        function broken(){throw new Error('合成错误');}
        function cyclic(){var a={};a.self=a;return a;}
        function bindings(){return [sourceApi.getKey(),baseUrl,typeof java,typeof cookie,typeof cache];}
        """
        let engine = try JsSourceEngine(source: source, client: ReplayHttpClient())
        XCTAssertEqual(try engine.callFunction("increment"), "1")
        XCTAssertEqual(try engine.callFunction("increment"), "1")
        XCTAssertNil(try engine.callFunction("missing", optional: true))
        XCTAssertThrowsError(try engine.callFunction("missing")) { XCTAssertTrue(String(describing: $0).contains("JS源缺少函数 missing")) }
        XCTAssertThrowsError(try engine.callFunction("broken")) { XCTAssertTrue(String(describing: $0).contains("合成错误")) }
        XCTAssertThrowsError(try engine.callFunction("cyclic"))
        XCTAssertEqual(try engine.callFunction("bindings"), "[\"https://example.invalid\",\"https://example.invalid\",\"object\",\"object\",\"object\"]")
        var book = Book(now: 0); book.bookUrl = "https://example.invalid/book"; book.name = "原名称"
        let info = try engine.bookInfo(book)
        XCTAssertEqual(info.book.name, "原名称")
        XCTAssertEqual(info.book.tocUrl, book.bookUrl)
    }

    func testMalformedResultsAndEmptyContent() throws {
        var source = try JsSourceConfig.extract(script)
        source.mainJs = "function search(){return {};}; function getChapters(){return [];} function getContent(){return ' ';}"
        let engine = try JsSourceEngine(source: source, client: ReplayHttpClient())
        XCTAssertThrowsError(try engine.search(key: "x"))
        let book = Book(now: 0)
        XCTAssertThrowsError(try engine.chapters(book: book)) { XCTAssertEqual($0 as? WebBookError, .emptyToc) }
        XCTAssertThrowsError(try engine.content(book: book, chapter: BookChapter())) { XCTAssertEqual($0 as? WebBookError, .emptyContent) }
    }

    func testStringifiedArraysAndSkippedInvalidRows() throws {
        var source = try JsSourceConfig.extract(script)
        source.mainJs = """
        function search(){return JSON.stringify([null,1,{}, {name:'有效',bookUrl:'book',type:16}]);}
        function getChapters(){return [null,{}, {title:'卷',url:'卷',isVolume:true},{title:'章',url:'read',index:99}];}
        """
        let engine = try JsSourceEngine(source: source, client: ReplayHttpClient())
        let books = try engine.search(key: "x")
        XCTAssertEqual(books.count, 1); XCTAssertEqual(books.first?.type, 8)
        var book = Book(now: 0); book.bookUrl = "book"; book.tocUrl = "https://example.invalid/toc/"
        let chapters = try engine.chapters(book: book)
        XCTAssertEqual(chapters.map(\.index), [0, 1]); XCTAssertEqual(chapters.first?.url, "卷")
        XCTAssertEqual(chapters.last?.url, "https://example.invalid/toc/read")
    }
}
