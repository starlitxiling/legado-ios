import Foundation
import LegadoCore

enum ImageRepositoryLoader {
    static func load(url: String, origin: String?, book: Book?, isCover: Bool,
                     sources: BookSourceRepository, cookies: CookieRepository, client: any HttpClient) async throws -> Data {
        let row = try await sources.get(bookSourceUrl: origin ?? "")
        let source = try row.map { try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode($0)) }
        let store = CookieStore()
        for cookie in try await cookies.list() { await store.setCookie(url: cookie.url, cookie: cookie.cookie) }
        return try await ImageDownloader(client: client, cookies: store).load(url: url, source: source, book: book, isCover: isCover)
    }
}
