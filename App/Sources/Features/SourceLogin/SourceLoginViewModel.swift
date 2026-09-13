import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class SourceLoginViewModel {
    let source: BookSource
    private let service: SourceLogin
    private(set) var rows: [LoginRow] = []
    var values: [String: String] = [:]
    private(set) var isBusy = false
    private(set) var completed = false
    var errorMessage: String?

    init(source: BookSource, service: SourceLogin) { self.source = source; self.service = service }
    func load() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            rows = try await service.rows(source: source)
            let stored = try await service.storedValues(source: source)
            values = Dictionary(uniqueKeysWithValues: rows.filter { !["button", "label"].contains($0.type) }
                .map { ($0.name, stored[$0.name] ?? $0.defaultValue ?? "") })
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func submit(action: String? = nil) async {
        guard !isBusy else { return }
        isBusy = true; completed = false; errorMessage = nil
        defer { isBusy = false }
        do {
            let effects = try await service.submit(source: source, values: values, action: action)
            if effects.renderRequested {
                let rendered = try await service.rows(source: source)
                if effects.deltaRender {
                    for row in rendered {
                        if let index = rows.firstIndex(where: { $0.name == row.name }) { rows[index] = row }
                        else { rows.append(row) }
                    }
                } else { rows = rendered }
                for row in rendered where values[row.name] == nil { values[row.name] = row.defaultValue ?? "" }
            }
            for (key, value) in effects.updates {
                values[key] = value ?? rows.first(where: { $0.name == key })?.defaultValue ?? ""
            }
            completed = true
        }
        catch { errorMessage = error.localizedDescription }
    }

    func completeWebLogin(cookies: [HTTPCookie], currentURL: URL?) async {
        guard !isBusy else { return }
        isBusy = true; completed = false; errorMessage = nil
        defer { isBusy = false }
        guard let currentURL, ["http", "https"].contains(currentURL.scheme?.lowercased() ?? "") else {
            errorMessage = "登录页面尚未加载完成"; return
        }
        do { try await service.saveWebCookies(cookies, url: currentURL); completed = true }
        catch { errorMessage = error.localizedDescription }
    }
}
