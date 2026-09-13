import Foundation
import CryptoKit

public actor HttpTTSSource {
    public enum SynthesisError: Error { case invalidResponse(Int), invalidContentType(String), emptyAudio }
    private struct Pending { let id: UUID; let task: Task<Data, Error> }
    private let source: HttpTTS
    private let client: any HttpClient
    private let directory: URL
    private let cookies: CookieStore
    private var database: AppDatabase?
    private let secrets: any SourceSecretStore
    private let maximumCacheBytes: Int
    private let maximumCacheAge: TimeInterval
    private let now: @Sendable () -> Date
    private let cache = HttpTTSCache.shared
    private var pending: [String: Pending] = [:]
    private var round = UUID()
    public var pendingCount: Int { pending.count }
    public init(source: HttpTTS, client: any HttpClient, directory: URL, cookies: CookieStore = JsEngine.sharedCookieStore,
                database: AppDatabase? = nil, secrets: any SourceSecretStore = MemorySourceSecretStore(),
                maximumCacheBytes: Int = 128 * 1024 * 1024, maximumCacheAge: TimeInterval = 600,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source; self.client = client; self.directory = directory; self.cookies = cookies
        self.database = database; self.secrets = secrets
        self.maximumCacheBytes = max(0, maximumCacheBytes); self.maximumCacheAge = max(0, maximumCacheAge); self.now = now
    }
    private func location(text: String, speed: Int) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(source)
        let key = SHA256.hash(data: encoded + Data("\u{0}\(speed)\u{0}\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".audio")
    }
    public func audio(text: String, speed: Int) async throws -> URL {
        try Task.checkCancellation()
        let token = round
        let destination = try location(text: text, speed: speed)
        try await cache.prepare(destination, directory: directory, maximumBytes: maximumCacheBytes, maximumAge: maximumCacheAge, now: now())
        do {
            let url = try await synthesize(text: text, speed: speed, destination: destination, token: token)
            try await cache.touch(url, now: now())
            try await trimCache()
            await cache.unpin(destination)
            return url
        } catch { await cache.unpin(destination); throw error }
    }
    private func synthesize(text: String, speed: Int, destination: URL, token: UUID) async throws -> URL {
        guard round == token else { throw CancellationError() }
        if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 { return destination }
        let key = destination.lastPathComponent
        let job: Pending
        if let existing = pending[key] { job = existing }
        else {
            if database == nil { database = try AppDatabase.inMemory() }
            let database = database!, source = source, client = client, cookies = cookies, secrets = secrets
            let task = Task<Data, Error> {
                for row in try await CookieRepository(database: database).list() { await cookies.setCookie(url: row.url, cookie: row.cookie) }
                let session = try HttpTTSScriptSession(source: source, database: database, client: client, cookies: cookies, secrets: secrets)
                for attempt in 0..<3 {
                    try Task.checkCancellation()
                    do {
                        let executor = try session.executor(text: text, speed: speed)
                        let raw: HttpResponse
                        do { raw = try await executor.getResponse() }
                        catch {
                            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                            let failed = HttpResponse(status: 500, body: Data(String(describing: error).utf8), finalURL: URL(string: executor.url)!)
                            let checked = try session.check(failed)
                            guard checked.status != 500 else { throw error }
                            return try Self.audioBytes(checked, source: source)
                        }
                        try Task.checkCancellation()
                        let response = try session.check(raw)
                        if source.enabledCookieJar == true {
                            var row = CookieRow(); row.url = CookieStore.hostKey(raw.finalURL.absoluteString)
                            row.cookie = await cookies.getCookie(url: row.url)
                            try await CookieRepository(database: database).upsert(row)
                        }
                        return try Self.audioBytes(response, source: source)
                    } catch {
                        if error is CancellationError || (error as? URLError)?.code == .cancelled || attempt == 2 { throw error }
                    }
                }
                throw SynthesisError.emptyAudio
            }
            job = Pending(id: UUID(), task: task); pending[key] = job
        }
        defer { if pending[key]?.id == job.id { pending[key] = nil } }
        let data = try await job.task.value
        try Task.checkCancellation()
        guard round == token else { throw CancellationError() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return destination
    }
    private static func audioBytes(_ response: HttpResponse, source: HttpTTS) throws -> Data {
        guard (200..<300).contains(response.status) else { throw SynthesisError.invalidResponse(response.status) }
        let mime = response.headers.first { $0.key.lowercased() == "content-type" }?.value.components(separatedBy: ";")[0] ?? ""
        guard !mime.hasPrefix("text/"), mime != "application/json" else { throw SynthesisError.invalidContentType(mime) }
        if let pattern = source.contentType, !pattern.isEmpty {
            let regex = try NSRegularExpression(pattern: "^(?:\(pattern))$")
            guard regex.firstMatch(in: mime, range: NSRange(location: 0, length: (mime as NSString).length)) != nil else { throw SynthesisError.invalidContentType(mime) }
        }
        guard !response.body.isEmpty else { throw SynthesisError.emptyAudio }
        return response.body
    }
    public func withAudio(text: String, speed: Int, maximumRecompositions: Int = 2,
                          play: @Sendable (URL) async throws -> Void) async throws {
        let token = round, destination = try location(text: text, speed: speed)
        try await cache.prepare(destination, directory: directory, maximumBytes: maximumCacheBytes, maximumAge: maximumCacheAge, now: now())
        do {
            for attempt in 0...max(0, maximumRecompositions) {
                try Task.checkCancellation()
                guard token == round else { throw CancellationError() }
                let url = try await audio(text: text, speed: speed)
                do { try await play(url); break }
                catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                    try await cache.remove(url)
                    if attempt == max(0, maximumRecompositions) { throw error }
                }
            }
            await cache.unpin(destination); try await trimCache()
        } catch { await cache.unpin(destination); try? await trimCache(); throw error }
    }
    public func prefetch(texts: [String], speed: Int) async {
        let token = round
        await withTaskGroup(of: Void.self) { group in
            for text in texts.prefix(2) {
                group.addTask { if !Task.isCancelled { _ = try? await self.prefetchAudio(text: text, speed: speed, token: token) } }
            }
        }
        try? await trimCache()
    }
    private func prefetchAudio(text: String, speed: Int, token: UUID) async throws {
        guard round == token else { throw CancellationError() }
        _ = try await audio(text: text, speed: speed)
    }
    public func cancel() { round = UUID(); for job in pending.values { job.task.cancel() }; pending.removeAll() }
    public func trimCache() async throws { try await cache.trim(directory: directory, maximumBytes: maximumCacheBytes, maximumAge: maximumCacheAge, now: now()) }
}
