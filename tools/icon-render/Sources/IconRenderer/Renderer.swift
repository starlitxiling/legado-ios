import Foundation
import CoreGraphics
import ImageIO

private final class Node {
    let name: String
    let attributes: [String: String]
    var children: [Node] = []
    var text = ""
    init(_ name: String, _ attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }
    subscript(_ key: String) -> String? { attributes["android:" + key] ?? attributes[key] }
    func number(_ key: String, _ fallback: CGFloat = 0) throws -> CGFloat {
        guard let text = self[key] else { return fallback }
        guard let value = Double(text), value.isFinite else { throw RenderError.invalid("无效数值：\(key)=\(text)") }
        return CGFloat(value)
    }
}

private final class Document: NSObject, XMLParserDelegate {
    var root: Node?
    var stack: [Node] = []
    static func parse(_ data: Data) throws -> Node {
        let document = Document()
        let parser = XMLParser(data: data)
        parser.delegate = document
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = document.root else {
            throw parser.parserError ?? RenderError.invalid("无效 XML")
        }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = Node(elementName, attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { stack.removeLast() }
}

public final class IconRenderer {
    private let resources: URL
    private var colors: [String: String] = [:]
    public init(resources: URL) throws {
        self.resources = resources
        let values = resources.appendingPathComponent("values")
        for url in try FileManager.default.contentsOfDirectory(at: values, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) where url.pathExtension == "xml" {
            for node in try Document.parse(Data(contentsOf: url)).children where node.name == "color" {
                if let name = node["name"] { colors[name] = node.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
    }

    private func color(_ text: String, alpha: CGFloat = 1, visited: Set<String> = []) throws -> CGColor {
        if text.hasPrefix("@color/") {
            let name = String(text.dropFirst(7))
            guard !visited.contains(name), let value = colors[name] else { throw RenderError.invalid("颜色缺失或循环引用：\(text)") }
            return try color(value, alpha: alpha, visited: visited.union([name]))
        }
        guard text.hasPrefix("#") else { throw RenderError.invalid("不支持的颜色：\(text)") }
        var hex = String(text.dropFirst())
        if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard [6, 8].contains(hex.count), let value = UInt32(hex, radix: 16) else { throw RenderError.invalid("无效颜色：\(text)") }
        let opacity = hex.count == 8 ? CGFloat((value >> 24) & 255) / 255 : 1
        return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, opacity * alpha])!
    }

    private func context(size: Int) throws -> CGContext {
        guard size > 0, size <= 4096, let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw RenderError.invalid("无法创建位图") }
        context.setFillColor(try color("#ffffff"))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    public func render(vector: Data, size: Int) throws -> CGImage {
        let context = try context(size: size)
        context.scaleBy(x: CGFloat(size) / 108, y: CGFloat(size) / 108)
        try draw(Document.parse(vector), in: context, visited: [])
        guard let image = context.makeImage() else { throw RenderError.invalid("无法创建图片") }
        return image
    }

    private func drawResource(_ reference: String, in context: CGContext, visited: Set<String>) throws {
        if reference.hasPrefix("@color/") || reference.hasPrefix("#") {
            context.setFillColor(try color(reference))
            context.fill(CGRect(x: 0, y: 0, width: 108, height: 108))
        } else {
            guard reference.hasPrefix("@drawable/"), !visited.contains(reference) else { throw RenderError.invalid("不支持或循环引用的 drawable：\(reference)") }
            let name = String(reference.dropFirst(10))
            guard !name.contains("/"), !name.contains("..") else { throw RenderError.invalid("无效资源名称") }
            let data = try Data(contentsOf: resources.appendingPathComponent("drawable/\(name).xml"))
            try draw(Document.parse(data), in: context, visited: visited.union([reference]))
        }
    }

    private func draw(_ node: Node, in context: CGContext, visited: Set<String>) throws {
        switch node.name {
        case "vector":
            let width = try node.number("viewportWidth"), height = try node.number("viewportHeight")
            guard width > 0, height > 0 else { throw RenderError.invalid("无效 viewport") }
            context.saveGState(); defer { context.restoreGState() }
            context.scaleBy(x: 108 / width, y: 108 / height)
            context.setAlpha(try node.number("alpha", 1))
            for child in node.children { try draw(child, in: context, visited: visited) }
        case "group":
            context.saveGState(); defer { context.restoreGState() }
            let px = try node.number("pivotX"), py = try node.number("pivotY")
            context.translateBy(x: try node.number("translateX") + px, y: try node.number("translateY") + py)
            context.rotate(by: try node.number("rotation") * .pi / 180)
            context.scaleBy(x: try node.number("scaleX", 1), y: try node.number("scaleY", 1))
            context.translateBy(x: -px, y: -py)
            for child in node.children { try draw(child, in: context, visited: visited) }
        case "clip-path":
            guard let data = node["pathData"] else { throw RenderError.invalid("clip-path 缺少 pathData") }
            context.addPath(try SVGPath.parse(data))
            context.clip(using: node["fillType"] == "evenOdd" ? .evenOdd : .winding)
        case "path":
            guard let data = node["pathData"], node.children.isEmpty else { throw RenderError.invalid("不支持的 path 内容") }
            let path = try SVGPath.parse(data)
            if let fill = node["fillColor"] {
                context.setFillColor(try color(fill, alpha: node.number("fillAlpha", 1)))
                context.addPath(path)
                context.fillPath(using: node["fillType"] == "evenOdd" ? .evenOdd : .winding)
            }
            if let stroke = node["strokeColor"], try node.number("strokeWidth") > 0 {
                context.setStrokeColor(try color(stroke, alpha: node.number("strokeAlpha", 1)))
                context.setLineWidth(try node.number("strokeWidth"))
                context.setLineCap(node["strokeLineCap"] == "round" ? .round : node["strokeLineCap"] == "square" ? .square : .butt)
                context.setLineJoin(node["strokeLineJoin"] == "round" ? .round : node["strokeLineJoin"] == "bevel" ? .bevel : .miter)
                context.setMiterLimit(try node.number("strokeMiterLimit", 4))
                context.addPath(path); context.strokePath()
            }
        case "adaptive-icon":
            for name in ["background", "foreground"] {
                guard let reference = node.children.first(where: { $0.name == name })?["drawable"] else { throw RenderError.invalid("缺少 \(name)") }
                context.saveGState()
                do { try drawResource(reference, in: context, visited: visited) }
                catch { context.restoreGState(); throw error }
                context.restoreGState()
            }
        default: throw RenderError.invalid("不支持的元素：\(node.name)")
        }
    }

    public func generate(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for number in 1...6 {
            let node = try Document.parse(Data(contentsOf: resources.appendingPathComponent("mipmap-anydpi-v26/launcher\(number).xml")))
            for (scale, size) in [(2, 120), (3, 180)] {
                let context = try context(size: size)
                // 108dp 图层取中心 72dp，输出不含系统圆角遮罩。
                context.scaleBy(x: CGFloat(size) / 72, y: CGFloat(size) / 72)
                context.translateBy(x: -18, y: -18)
                try draw(node, in: context, visited: [])
                let url = directory.appendingPathComponent("launcher\(number)@\(scale)x.png")
                guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw RenderError.invalid("无法写入 PNG") }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw RenderError.invalid("PNG 写入失败") }
            }
        }
    }
}
