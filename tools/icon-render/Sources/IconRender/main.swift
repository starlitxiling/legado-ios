import Foundation
import IconRenderer

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("用法：IconRender <Android res 目录> <PNG 输出目录>\n", stderr)
    exit(2)
}
do {
    try IconRenderer(resources: URL(fileURLWithPath: arguments[1])).generate(to: URL(fileURLWithPath: arguments[2]))
    print("已生成六套备用图标，共 12 张 PNG。")
} catch {
    fputs("图标生成失败：\(error)\n", stderr)
    exit(1)
}
