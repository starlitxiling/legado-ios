import Foundation
import LegadoCore
#if canImport(FoundationXML)
import FoundationXML
#endif

enum ReaderReviewIconStyle {
    static let builtins: [(String, String)] = [
        ("对话框", #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 24"><path d="M2 2h28v16H12l-7 5v-5H2z" fill="none" stroke="black" stroke-width="2"/><text x="16" y="14" text-anchor="middle" font-size="12">{{count}}</text></svg>"#),
        ("圆角气泡", #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 24"><rect x="1" y="1" width="30" height="22" rx="10" fill="none" stroke="black" stroke-width="2"/><text x="16" y="16" text-anchor="middle" font-size="14">{{count}}</text></svg>"#)
    ]

    static func aspectRatio(_ svg: String) throws -> Double {
        guard svg.utf8.count <= 65_536, !svg.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !svg.localizedCaseInsensitiveContains("<!ENTITY") else { throw ReaderIconError.invalidSVG }
        let parser = XMLParser(data: Data(svg.replacingOccurrences(of: "{{count}}", with: "88").utf8))
        let validator = Validator()
        parser.shouldResolveExternalEntities = false; parser.delegate = validator
        guard parser.parse(), validator.valid, let ratio = validator.ratio, ratio > 0, ratio <= 4 else { throw ReaderIconError.invalidSVG }
        return ratio
    }

    static func document(_ svg: String, count: Int) throws -> String {
        _ = try aspectRatio(svg)
        return svg.replacingOccurrences(of: "{{count}}", with: String(min(999, max(0, count))))
    }

    static func saveTemplate(name: String, svg: String, configuration: inout ReadBookConfig) throws {
        let normalized = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try aspectRatio(normalized)
        var template = ReviewIconSvgTemplate()
        template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if template.name.isEmpty { template.name = "自定义图标" }
        template.svg = normalized
        configuration.reviewIconSvgTemplates.removeAll { $0.svg == normalized }
        configuration.reviewIconSvgTemplates.append(template)
        configuration.reviewIconSvg = normalized
    }

    private final class Validator: NSObject, XMLParserDelegate {
        var valid = true
        var ratio: Double?
        private var depth = 0
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            if depth == 0 {
                guard elementName == "svg" else { valid = false; parser.abortParsing(); return }
                let box = attributes["viewBox"]?.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { Double($0) } ?? []
                let width = box.count == 4 ? box[2] : Double(attributes["width"] ?? "24") ?? 24
                let height = box.count == 4 ? box[3] : Double(attributes["height"] ?? "24") ?? 24
                ratio = width.isFinite && height.isFinite && width > 0 && height > 0 ? width / height : nil
            }
            depth += 1
            if ["script", "foreignobject"].contains(elementName.lowercased()) { valid = false }
            for (key, value) in attributes {
                if key.lowercased().hasPrefix("on") { valid = false }
                if key.lowercased().hasSuffix("href"), !value.hasPrefix("#") { valid = false }
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { depth -= 1 }
    }
}

enum ReaderIconError: LocalizedError {
    case invalidSVG
    var errorDescription: String? { "段评图标 SVG 无效。请使用不超过 64 KB、宽高比不超过 4 的 SVG，移除脚本和外部资源后重试。" }
}
