import XCTest
@testable import LegadoCore

final class JavaHostCacheTests: XCTestCase {
    func testBinaryFileAndObjectMemoryRemainSeparate() throws {
        let engine = JsEngine(cacheManager: CacheManager(directory: nil))
        XCTAssertEqual(try engine.evaluateScript("cache.put('key',new Uint8Array([0,255,65]));Array.from(cache.getByteArray('key')).join(',')") as? String, "0,255,65")
        XCTAssertEqual(try engine.evaluateScript("cache.get('key') === null") as? Bool, true)
        XCTAssertEqual(try engine.evaluateScript("cache.putFile('file','Text');cache.getFile('file')") as? String, "Text")
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(cache.getByteArray('file'))") as? String, "Text")
        XCTAssertEqual(try engine.evaluateScript("cache.putMemory('object',{count:3,values:['a','b']});cache.getFromMemory('object').values.join(',')") as? String, "a,b")
        XCTAssertEqual(try engine.evaluateScript("cache.get('object') === null") as? Bool, true)
        XCTAssertEqual(try engine.evaluateScript("cache.deleteMemory('object');cache.getFromMemory('object')===null") as? Bool, true)
        XCTAssertEqual(try engine.evaluateScript("cache.put('file','Disk');cache.putMemory('file','Memory');[cache.get('file'),cache.get('file',true),cache.getFile('file')].join('|')") as? String, "Memory|Disk|Text")
        XCTAssertEqual(try engine.evaluateScript("cache.delete('file');[cache.get('file'),cache.getFile('file'),cache.getFromMemory('file')].every(v=>v===null)") as? Bool, true)
    }

    func testBinaryFilePersistenceAndExpiry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = CacheManager(directory: directory, now: { 1000 })
        let engine = JsEngine(cacheManager: first)
        _ = try engine.evaluateScript("cache.put('bytes',new Uint8Array([65]),1);cache.putFile('permanent','saved')")
        let reopened = JsEngine(cacheManager: CacheManager(directory: directory, now: { 1999 }))
        XCTAssertEqual(try reopened.evaluateScript("java.bytesToStr(cache.getByteArray('bytes'))") as? String, "A")
        let expired = JsEngine(cacheManager: CacheManager(directory: directory, now: { 2000 }))
        XCTAssertEqual(try expired.evaluateScript("cache.getByteArray('bytes') === null") as? Bool, true)
        XCTAssertEqual(try expired.evaluateScript("cache.getFile('permanent')") as? String, "saved")
    }
    func testMemoryCachePreservesTypesAndEvictsLeastRecentlyUsed() throws {
        let engine = JsEngine(cacheManager: CacheManager(directory: nil, memoryLimit: 12))
        XCTAssertEqual(try engine.evaluateScript("cache.putMemory('a','aaa');cache.putMemory('b','bbb');cache.getFromMemory('a');cache.putMemory('c','ccc');cache.getFromMemory('b')===null") as? Bool, true)
        XCTAssertEqual(try engine.evaluateScript("cache.getFromMemory('a')") as? String, "aaa")
        _ = try engine.evaluateScript("cache.putMemory('large','1234567')")
        XCTAssertEqual(try engine.evaluateScript("cache.getFromMemory('large')===null") as? Bool, true)
        let numbers = JsEngine(cacheManager: CacheManager(directory: nil))
        XCTAssertEqual(try numbers.evaluateScript("cache.putMemory('double',1.5);cache.getDouble('double')") as? Double, 1.5)
        XCTAssertEqual(try numbers.evaluateScript("cache.putMemory('bytes',new Uint8Array([0,255]));Array.from(cache.getFromMemory('bytes')).join(',')") as? String, "0,255")
        XCTAssertEqual(try numbers.evaluateScript("cache.putMemory('flag',true);cache.getFromMemory('flag')===true") as? Bool, true)
    }

}
