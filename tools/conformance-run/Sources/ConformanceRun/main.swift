import Foundation
import LegadoCore

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

private func compact(_ text: String, limit: Int = 400) -> String {
    let escaped = text.replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
    return escaped.count <= limit ? escaped : String(escaped.prefix(limit)) + "... [truncated]"
}

private func displayPath(_ url: URL) -> String {
    let prefix = repositoryRoot.path + "/"
    return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
}

private func decodingReason(_ error: DecodingError) -> String {
    let context: DecodingError.Context
    let reason: String
    switch error {
    case .keyNotFound(let key, let value):
        context = value
        reason = "missing key \(key.stringValue)"
    case .typeMismatch(let type, let value):
        context = value
        reason = "expected \(type)"
    case .valueNotFound(let type, let value):
        context = value
        reason = "missing value of type \(type)"
    case .dataCorrupted(let value):
        context = value
        reason = "invalid data"
    @unknown default:
        return compact(String(describing: error))
    }
    let path = context.codingPath.map(\.stringValue).joined(separator: ".")
    return compact("ConformanceCase[] decode: \(reason) at \(path.isEmpty ? "$" : path); \(context.debugDescription)")
}

private func collectFiles(_ paths: [URL]) throws -> [URL] {
    var files: Set<URL> = []
    func visit(_ url: URL) throws {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            guard visited.insert(url).inserted else { return }
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                try visit(child)
            }
        } else if values.isRegularFile == true && url.pathExtension.lowercased() == "json" {
            files.insert(url)
        }
    }
    var visited: Set<URL> = []
    for path in paths { try visit(path) }
    return files.sorted { $0.path < $1.path }
}

private func main() -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] {
        print("Usage: conformance-run [file-or-directory ...]")
        print("Default: Tests/Conformance/fixtures relative to the source repository; explicit paths are relative to the current directory.")
        return 0
    }
    let paths = arguments.isEmpty
        ? [repositoryRoot.appendingPathComponent("Tests/Conformance/fixtures")]
        : arguments.map { URL(fileURLWithPath: $0) }
    do {
        let files = try collectFiles(paths)
        let explicitPaths = Set(arguments.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath() })
        var fixtureCount = 0
        var nonCaseCount = 0
        var total = 0
        var passed = 0
        var failed = 0
        var skipped = 0
        var unsupported = 0
        var errors = 0
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let cases: [ConformanceCase]
                do {
                    cases = try JSONDecoder().decode([ConformanceCase].self, from: data)
                } catch let error as DecodingError {
                    if explicitPaths.contains(file) {
                        errors += 1
                        print("ERROR \(displayPath(file)): \(decodingReason(error))")
                        continue
                    }
                    nonCaseCount += 1
                    print("SKIP \(displayPath(file)): 非用例夹具，已跳过; \(decodingReason(error))")
                    continue
                }
                fixtureCount += 1
                let results = ConformanceRunner.run(cases).results
                let filePassed = results.filter { $0.status == .passed }.count
                total += results.count
                passed += filePassed
                print("FILE \(displayPath(file)): \(filePassed) / \(results.count)")
                for result in results where result.status != .passed {
                    switch result.status {
                    case .failed: failed += 1
                    case .skipped: skipped += 1
                    case .unsupported: unsupported += 1
                    case .passed: break
                    }
                    print("  \(result.status.rawValue.uppercased()) id=\(compact(result.id)) kind=\(compact(result.kind))")
                    print("    expected=\(compact(String(describing: result.expected)))")
                    print("    actual=\(result.actual.map { compact(String(describing: $0)) } ?? "<none>")")
                    if !result.detail.isEmpty { print("    detail=\(compact(result.detail))") }
                }
            } catch {
                errors += 1
                print("ERROR \(displayPath(file)): \(compact(String(describing: error)))")
            }
        }
        let rate = total == 0 ? "N/A" : String(format: "%.2f%%", Double(passed) / Double(total) * 100)
        print("SUMMARY json_files=\(files.count) case_files=\(fixtureCount) non_case_files=\(nonCaseCount)")
        print("TOTAL \(passed) / \(total) / \(rate); failed=\(failed) skipped=\(skipped) unsupported=\(unsupported) errors=\(errors)")
        if total == 0 { print("ERROR No conformance cases found in the selected paths.") }
        return total > 0 && passed == total && errors == 0 ? 0 : 1
    } catch {
        print("ERROR Cannot scan requested paths \(paths.map(\.path)): \(compact(String(describing: error)))")
        return 1
    }
}

exit(main())
