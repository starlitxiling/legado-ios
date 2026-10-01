import SwiftUI
import LegadoCore

struct ReaderInfoView: View {
    let settings: ReaderSettings
    let header: Bool
    var values: ReaderInfoValues

    static func height(settings: ReaderSettings, header: Bool) -> CGFloat {
        let config = settings.configuration
        if header && (config.headerMode == 2 || (config.headerMode == 0 && !settings.hidesStatusBar)) { return 0 }
        if !header && config.footerMode == 1 { return 0 }
        let top = header ? config.headerPaddingTop : config.footerPaddingTop
        let bottom = header ? config.headerPaddingBottom : config.footerPaddingBottom
        return CGFloat(top + bottom) + CGFloat(min(50, max(5, config.tipTextSize))) * 1.4 + 1
    }

    var body: some View {
        let config = settings.configuration
        if Self.height(settings: settings, header: header) > 0 {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let color = config.tipColor == 0 ? Color(cgColor: ReaderTypography.bodyColor(settings))
                    : ARGBColor(UInt32(truncatingIfNeeded: config.tipColor)).color
                let divider = config.tipDividerColor == -1 ? color : ARGBColor(UInt32(truncatingIfNeeded: config.tipDividerColor)).color
                VStack(spacing: 0) {
                    if !header && config.showFooterLine { divider.opacity(0.35).frame(height: 0.5) }
                    HStack(spacing: 4) {
                        slot(header ? config.tipHeaderLeft : config.tipFooterLeft,
                             template: header ? config.tipHeaderLeftTemplate : config.tipFooterLeftTemplate, date: context.date)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        slot(header ? config.tipHeaderMiddle : config.tipFooterMiddle,
                             template: header ? config.tipHeaderMiddleTemplate : config.tipFooterMiddleTemplate, date: context.date)
                            .frame(maxWidth: .infinity, alignment: .center)
                        slot(header ? config.tipHeaderRight : config.tipFooterRight,
                             template: header ? config.tipHeaderRightTemplate : config.tipFooterRightTemplate, date: context.date)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: CGFloat(min(50, max(5, config.tipTextSize)))))
                    .foregroundStyle(color).lineLimit(1)
                    .frame(height: CGFloat(min(50, max(5, config.tipTextSize))) * 1.4)
                    if header && config.showHeaderLine { divider.opacity(0.35).frame(height: 0.5) }
                }
                .padding(.top, CGFloat(header ? config.headerPaddingTop : config.footerPaddingTop))
                .padding(.bottom, CGFloat(header ? config.headerPaddingBottom : config.footerPaddingBottom))
                .padding(.leading, CGFloat(header ? config.headerPaddingLeft : config.footerPaddingLeft))
                .padding(.trailing, CGFloat(header ? config.headerPaddingRight : config.footerPaddingRight))
            }.frame(height: Self.height(settings: settings, header: header))
        }
    }

    private func slot(_ code: Int, template: String?, date: Date) -> some View {
        var current = values
        current.time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        current.battery = Int(max(0, UIDevice.current.batteryLevel) * 100)
        let parts = ReaderInfo.parts(code: code, template: template, values: current)
        return HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let value): Text(value)
                case .battery(let level, let showLevel):
                    Image(systemName: "battery.\(Int((Double(level) / 25).rounded()) * 25)percent")
                        .accessibilityLabel("电量 \(level)%")
                    if showLevel { Text("\(level)") }
                }
            }
        }
    }
}

struct ReaderBackgroundView: View {
    let settings: ReaderSettings
    var maximumPixelSize: Int? = nil
    @State private var image: UIImage?
    @State private var loadError: String?
    private var value: String { settings.backgroundValue }
    private var type: Int { settings.backgroundType }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                (settings.theme == .night ? Color.black : Color.white)
                if type == 0 { (ARGBColor(hex: value) ?? ARGBColor(0xFFEEEEEE)).color }
                else if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .opacity(Double(settings.configuration.bgAlpha) / 100)
                        .accessibilityLabel("背景图片：" + value)
                        .accessibilityIdentifier("reader.background.image")
                }
                if let loadError { Text(loadError).font(.caption).padding().frame(maxHeight: .infinity, alignment: .bottom) }
            }
        }.task(id: "\(type):\(value)") {
            image = nil; loadError = nil
            guard type != 0 else { return }
            let name = (value as NSString).lastPathComponent
            let root = URL.applicationSupportDirectory.appendingPathComponent("Legado/bg", isDirectory: true)
            do {
                guard let url = try settings.backgroundImageURL(directory: root) else { return }
                let loaded = try await ReaderBackgroundImageStore.shared.image(at: url,
                    maximumPixelSize: maximumPixelSize ?? ReaderBackgroundImageStore.screenPixelSize)
                try Task.checkCancellation()
                image = loaded
            } catch is CancellationError {
            } catch { loadError = "背景图片无法读取：\(name)" }
        }
    }
}
