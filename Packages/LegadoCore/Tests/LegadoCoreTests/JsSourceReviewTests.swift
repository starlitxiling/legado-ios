import XCTest
@testable import LegadoCore

final class JsSourceReviewTests: XCTestCase {
    private func source(_ script: String = "") -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = "https://example.invalid/review"
        source.bookSourceName = "复审源"
        source.mainJs = script
        return source
    }

    func testMainJsLoginPersistsCredentialsAndCheckUsesSameScript() async throws {
        let database = try AppDatabase.inMemory()
        let secrets = MemorySourceSecretStore()
        let login = SourceLogin(database: database, client: ReplayHttpClient(), secrets: secrets)
        var value = source("""
        function login(){
          var info=source.getLoginInfoMap();
          source.put('account',info.get('account'));
          source.putLoginHeader(JSON.stringify({Authorization:'Bearer '+info.get('password')}));
        }
        """)
        value.loginUrl = "@js:function login(){throw new Error('错误的登录脚本');}"
        try await login.submit(source: value, values: ["account": "reader", "password": "synthetic"])
        let restored = SourceLogin(database: database, client: ReplayHttpClient(), secrets: secrets)
        let stored = try await restored.storedValues(source: value)
        XCTAssertEqual(stored, ["account": "reader", "password": "synthetic"])
        let state = try await SourceStateRepository(database: database).load(source: value.bookSourceUrl!)
        XCTAssertNil(state["loginInfo"])
        XCTAssertEqual(state["v_account"], "reader")
        value.loginUrl = nil
        value.loginCheckJs = "login(); source.login(); result"
        let response = HttpResponse(status: 200, finalURL: URL(string: value.bookSourceUrl!)!)
        let checked = try await restored.check(source: value, response: response)
        XCTAssertEqual(checked, response)
    }

    func testStringConfigWinsOverLegacyObjectAfterNormalization() throws {
        let extracted = try JsSourceConfig.extract("""
        var config=JSON.stringify({bookSourceName:'现代',bookSourceUrl:'https://example.invalid/new'});
        var source={bookSourceName:'旧版',bookSourceUrl:'https://example.invalid/old'};
        function search(){} function getChapters(){} function getContent(){}
        """)
        XCTAssertEqual(extracted.bookSourceName, "现代")
    }

    func testWhitespaceConfigFallsBackToLegacyString() throws {
        let extracted = try JsSourceConfig.extract("""
        var config={bookSourceName:'  ',bookSourceUrl:'https://example.invalid/new'};
        var source=JSON.stringify({bookSourceName:'旧版',bookSourceUrl:'https://example.invalid/old'});
        function search(){} function getChapters(){} function getContent(){}
        """)
        XCTAssertEqual(extracted.bookSourceName, "旧版")
    }

    private let baseMethods = ["getTag", "getKey", "getSource", "getLoginUiJs", "isLoginUiV2",
        "evalLoginUiV2", "evalLoginActionV2", "getLoginJs", "hasLoginForm", "hasLogin", "login",
        "getHeaderMap", "getLoginHeader", "getLoginHeaderMap", "putLoginHeader", "removeLoginHeader",
        "getLoginInfo", "getLoginInfoMap", "putLoginInfo", "removeLoginInfo", "setVariable", "putVariable",
        "getVariable", "put", "get", "refreshExplore", "refreshJSLib", "putConcurrent", "evalJS"]

    func testBaseSourceMethodsOnPlainAndPersistentClients() throws {
        let database = try AppDatabase.inMemory()
        let names = String(decoding: try JSONEncoder().encode(baseMethods), as: UTF8.self)
        let value = source("function missing(){return \(names).filter(function(n){return typeof sourceApi[n] !== 'function';});}")
        for client in [ReplayHttpClient() as any HttpClient,
                       SourceSessionHttpClient(source: value, database: database, client: ReplayHttpClient())] {
            XCTAssertEqual(try JsSourceEngine(source: value, client: client).callFunction("missing"), "[]")
        }
    }

    func testLoginHeaderMapsAndInfoMapsOnBothClients() throws {
        let database = try AppDatabase.inMemory()
        let value = source("""
        function inspect(){
          if(sourceApi.getLoginHeaderMap() !== null) throw 'missing header should be null';
          sourceApi.putLoginHeader('{"Authorization":"synthetic"}');
          var first=sourceApi.getLoginHeaderMap().get('Authorization');
          sourceApi.putLoginHeader('not-json');
          if(sourceApi.getLoginHeaderMap() !== null) throw 'invalid header should be null';
          sourceApi.putLoginInfo('not-json');
          var info=sourceApi.getLoginInfoMap().get('missing');
          sourceApi.removeLoginInfo(); sourceApi.removeLoginHeader();
          return [first, info, sourceApi.getLoginInfo(), sourceApi.getLoginHeader()];
        }
        """)
        for client in [ReplayHttpClient() as any HttpClient,
                       SourceSessionHttpClient(source: value, database: database, client: ReplayHttpClient())] {
            XCTAssertEqual(try JsSourceEngine(source: value, client: client).callFunction("inspect"), "[\"synthetic\",null,null,null]")
        }
    }

    func testVariableNamespacesAndNullDeletionOnBothClients() throws {
        let database = try AppDatabase.inMemory()
        let value = source("""
        function write(){sourceApi.put('variable','key-value');sourceApi.setVariable('source-value');return [sourceApi.get('variable'),sourceApi.getVariable()];}
        function clear(){sourceApi.setVariable(null);return [sourceApi.get('variable'),sourceApi.getVariable()];}
        function alias(){sourceApi.putVariable('alias');sourceApi.putVariable(null);return [sourceApi.get('variable'),sourceApi.getVariable()];}
        """)
        for client in [ReplayHttpClient() as any HttpClient,
                       SourceSessionHttpClient(source: value, database: database, client: ReplayHttpClient())] {
            let engine = try JsSourceEngine(source: value, client: client)
            XCTAssertEqual(try engine.callFunction("write"), "[\"key-value\",\"source-value\"]")
            XCTAssertEqual(try engine.callFunction("clear"), "[\"key-value\",\"\"]")
            XCTAssertEqual(try engine.callFunction("alias"), "[\"key-value\",\"\"]")
        }
        XCTAssertNil(try SourceStateRepository(database: database).value(source: value.bookSourceUrl!, key: "variable"))
    }

    func testHeaderDefaultsDynamicLoginInfoAndIsolatedEvaluation() throws {
        let database = try AppDatabase.inMemory()
        var value = source("""
        var outerOnly=42;
        function defaults(){return [{name:'account',default:'reader'},{name:'submit',type:'button'}];}
        function inspect(){
          sourceApi.putLoginHeader('{"Authorization":"login"}');
          return [sourceApi.getSource() === sourceApi,sourceApi.hasLogin(),sourceApi.hasLoginForm(),
            sourceApi.getHeaderMap(true).get('Authorization'),sourceApi.getHeaderMap().get('User-Agent'),
            sourceApi.getLoginInfoMap().get('account'),sourceApi.getLoginInfoMap().get('submit'),
            sourceApi.evalJS('typeof outerOnly')];
        }
        """)
        value.header = "@js: JSON.stringify({Authorization:'base','User-Agent':'synthetic'})"
        value.loginUi = "<js>defaults()</js>"
        for client in [ReplayHttpClient() as any HttpClient,
                       SourceSessionHttpClient(source: value, database: database, client: ReplayHttpClient())] {
            XCTAssertEqual(try JsSourceEngine(source: value, client: client).callFunction("inspect"),
                           "[true,true,true,\"login\",\"synthetic\",\"reader\",null,\"undefined\"]")
        }
    }
}
