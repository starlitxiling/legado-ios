import SwiftUI
import CoreText
import UIKit
import LegadoCore

@MainActor struct ConfiguredCoverView: View {
    let title: String
    let author: String
    let preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let night = colorScheme == .dark
            let text = preferences.coverText(title: title, author: author, night: night)
            let horizontal = preferences.boolean("coverHorizontal")
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.color(preferences.integer(night ? "colorBottomBackgroundNight" : "colorBottomBackground")))
                SettingsImage(path: background(night: night)).clipped()
                let layout = horizontal ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                layout {
                    if let title = text.title, !title.isEmpty {
                        titleView(title, geometry: geometry.size, horizontal: horizontal)
                    }
                    if !horizontal { Spacer(minLength: 0) }
                    if let author = text.author, !author.isEmpty {
                        Text(horizontal ? author : author.map(String.init).joined(separator: "\n"))
                            .font(font(size: textSize(author, title: false, geometry: geometry.size, horizontal: horizontal)))
                            .lineLimit(horizontal ? 1 : nil)
                            .padding(.top, horizontal ? 0 : max(0, geometry.size.height * 0.75 - Double(author.count) * nativeFont(size: textSize(author, title: false, geometry: geometry.size, horizontal: horizontal)).lineHeight))
                    }
                }.padding(6)
            }
        }.clipped()
    }

    private func background(night: Bool) -> String {
        let key = night ? "defaultCoverDark" : "defaultCover"
        let path = preferences.string(key)
        if !path.isEmpty, !path.hasPrefix("/") || FileManager.default.fileExists(atPath: path) { return path }
        return BackupResources.defaultDirectory.appendingPathComponent("covers/" + key + ".image").path
    }

    private func titleView(_ title: String, geometry: CGSize, horizontal: Bool) -> some View {
        let size = textSize(title, title: true, geometry: geometry, horizontal: horizontal)
        let large = geometry.width / 7 * (preferences.boolean("coverCustomFontSize") ? Double(max(50, min(200, preferences.integer("coverTitleLargeSize")))) / 100 : 1)
        let adaptive = preferences.boolean("coverTitleAdaptive")
        let firstSize = adaptive ? size : large
        let capacity = max(1, horizontal ? Int(geometry.width * 0.78 / max(1, firstSize)) : Int(geometry.height * 0.6 / max(1, nativeFont(size: firstSize).lineHeight)))
        let first = String(title.prefix(capacity))
        let remaining = String(title.dropFirst(capacity))
        return Group {
            if horizontal {
                (Text(first).font(font(size: firstSize))
                    + Text((remaining.isEmpty ? "" : "\n") + remaining).font(font(size: size)))
                    .multilineTextAlignment(.center)
            } else {
                let columns = CoverTypography.columns(title, capacity: capacity)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        Text(column.map(String.init).joined(separator: "\n"))
                            .font(font(size: index == 0 ? firstSize : size))
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(.top, Double(index) * nativeFont(size: size).lineHeight)
                    }
                }
            }
        }
    }

    private func textSize(_ text: String, title: Bool, geometry: CGSize, horizontal: Bool) -> Double {
        let key = title ? "coverTitle" : "coverAuthor"
        return CoverTypography.size(width: geometry.width, divisor: title ? 7 : 10,
            large: preferences.integer(key + "LargeSize"), small: preferences.integer(key + "SmallSize"),
            custom: preferences.boolean("coverCustomFontSize")) { size in
                let measured = (text as NSString).size(withAttributes: [.font: nativeFont(size: size)])
                return horizontal ? measured.width <= geometry.width * (title ? 0.78 : 0.65)
                    : Double(text.count) * nativeFont(size: size).lineHeight <= geometry.height * (title ? 0.6 : 0.65)
            }
    }

    private func font(size: Double) -> Font {
        Font(nativeFont(size: size))
    }

    private func nativeFont(size: Double) -> UIFont {
        let value = preferences.string("coverFont")
        switch CoverFontReference(value) {
        case .none:
            return .systemFont(ofSize: size)
        case .name(let name):
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        case .file(let url):
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let descriptor = descriptors.first,
               let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
            }
            return .systemFont(ofSize: size)
        }
    }
}
