import Foundation
import CoreGraphics

public enum RenderError: Error {
    case invalid(String)
}

public enum SVGPath {
    public static func parse(_ text: String) throws -> CGPath {
        let scanner = Scanner(string: text)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\r\t")
        let path = CGMutablePath()
        var command: Character?
        var previous: Character?
        var current = CGPoint.zero
        var start = CGPoint.zero
        var control = CGPoint.zero
        func number() throws -> CGFloat {
            guard let value = scanner.scanDouble(), value.isFinite else { throw RenderError.invalid("路径缺少数值：\(text)") }
            return CGFloat(value)
        }
        func flag() throws -> Bool {
            if scanner.scanString("0") != nil { return false }
            if scanner.scanString("1") != nil { return true }
            throw RenderError.invalid("弧线标志必须为 0 或 1")
        }
        while !scanner.isAtEnd {
            while scanner.currentIndex < text.endIndex, " ,\n\r\t".contains(text[scanner.currentIndex]) {
                scanner.currentIndex = text.index(after: scanner.currentIndex)
            }
            let letter = text[scanner.currentIndex]
            if letter.isLetter {
                guard "MmLlHhVvCcSsQqTtAaZz".contains(letter) else { throw RenderError.invalid("不支持的路径命令：\(letter)") }
                scanner.currentIndex = text.index(after: scanner.currentIndex)
                command = letter
            }
            guard let op = command else { throw RenderError.invalid("缺少路径命令") }
            let upper = Character(String(op).uppercased())
            guard !path.isEmpty || upper == "M" else { throw RenderError.invalid("路径必须从 M 开始") }
            let relative = op.isLowercase
            let origin = current
            func point() throws -> CGPoint {
                let x = try number(), y = try number()
                return CGPoint(x: x + (relative ? origin.x : 0), y: y + (relative ? origin.y : 0))
            }
            func reflected(_ kinds: String) -> CGPoint {
                guard let previous, kinds.contains(previous) else { return current }
                return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
            }
            switch upper {
            case "M":
                current = try point(); start = current; path.move(to: current)
                command = relative ? "l" : "L"
            case "L": current = try point(); path.addLine(to: current)
            case "H": current.x = try number() + (relative ? origin.x : 0); path.addLine(to: current)
            case "V": current.y = try number() + (relative ? origin.y : 0); path.addLine(to: current)
            case "C":
                let first = try point(), second = try point(), end = try point()
                path.addCurve(to: end, control1: first, control2: second); control = second; current = end
            case "S":
                let first = reflected("CS"), second = try point(), end = try point()
                path.addCurve(to: end, control1: first, control2: second); control = second; current = end
            case "Q":
                let first = try point(), end = try point()
                path.addQuadCurve(to: end, control: first); control = first; current = end
            case "T":
                let first = reflected("QT"), end = try point()
                path.addQuadCurve(to: end, control: first); control = first; current = end
            case "A":
                let rx = try number(), ry = try number(), rotation = try number()
                let large = try flag(), sweep = try flag(), end = try point()
                arc(path, from: current, to: end, rx: abs(rx), ry: abs(ry), rotation: rotation, large: large, sweep: sweep)
                current = end
            case "Z": path.closeSubpath(); current = start; command = nil
            default: throw RenderError.invalid("不支持的路径命令")
            }
            previous = upper
        }
        return path
    }

    private static func arc(_ path: CGMutablePath, from start: CGPoint, to end: CGPoint,
                            rx inputRX: CGFloat, ry inputRY: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        guard start != end else { return }
        guard inputRX > 0, inputRY > 0 else { path.addLine(to: end); return }
        let phi = rotation * .pi / 180, c = cos(phi), s = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x = c * dx + s * dy, y = -s * dx + c * dy
        let correction = max(1, sqrt(x * x / (inputRX * inputRX) + y * y / (inputRY * inputRY)))
        let rx = inputRX * correction, ry = inputRY * correction
        let denominator = rx * rx * y * y + ry * ry * x * x
        let factor = (large == sweep ? -1.0 : 1.0) * sqrt(max(0, (rx * rx * ry * ry - denominator) / denominator))
        let cx = factor * rx * y / ry, cy = -factor * ry * x / rx
        let center = CGPoint(x: c * cx - s * cy + (start.x + end.x) / 2,
                             y: s * cx + c * cy + (start.y + end.y) / 2)
        let first = atan2((y - cy) / ry, (x - cx) / rx)
        var delta = atan2((-y - cy) / ry, (-x - cx) / rx) - first
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        let count = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(count)
        func point(_ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + c * rx * cos(angle) - s * ry * sin(angle),
                    y: center.y + s * rx * cos(angle) + c * ry * sin(angle))
        }
        func tangent(_ angle: CGFloat) -> CGPoint {
            CGPoint(x: -c * rx * sin(angle) - s * ry * cos(angle), y: -s * rx * sin(angle) + c * ry * cos(angle))
        }
        for index in 0..<count {
            let a = first + CGFloat(index) * step, b = a + step, k = 4 / 3 * tan(step / 4)
            let p = point(a), q = point(b), u = tangent(a), v = tangent(b)
            path.addCurve(to: index == count - 1 ? end : q,
                          control1: CGPoint(x: p.x + k * u.x, y: p.y + k * u.y),
                          control2: CGPoint(x: q.x - k * v.x, y: q.y - k * v.y))
        }
    }
}
