import Foundation

enum LegadoIcon {
    static let symbols: [String: String] = [
        "ic_bottom_books": "books.vertical", "ic_bottom_explore": "safari",
        "ic_bottom_rss_feed": "dot.radiowaves.left.and.right", "ic_bottom_person": "person.crop.circle",
        "ic_search": "magnifyingglass", "ic_more_vert": "ellipsis", "ic_toc": "list.bullet",
        "ic_read_aloud": "speaker.wave.2", "ic_interface_setting": "textformat.size", "ic_settings": "gearshape",
        "ic_brightness": "moon", "ic_brightness_auto": "sun.max", "ic_auto_page": "play.rectangle",
        "ic_auto_page_stop": "stop.circle", "ic_find_replace": "arrow.2.squarepath", "ic_bookmark": "bookmark",
        "ic_bookmark_filled": "bookmark.fill", "ic_edit": "pencil", "ic_add": "plus", "ic_import": "square.and.arrow.down",
        "ic_export": "square.and.arrow.up", "ic_scan": "qrcode.viewfinder", "ic_share": "square.and.arrow.up",
        "ic_refresh_black_24dp": "arrow.clockwise", "ic_exchange": "arrow.left.arrow.right", "ic_groups": "folder",
        "ic_sort": "arrow.up.arrow.down", "ic_author": "person", "ic_history": "clock.arrow.circlepath",
        "ic_check_source": "checkmark.seal", "ic_backup": "externaldrive", "ic_web_outline": "globe",
        "ic_screen": "rotate.right", "ic_cfg_source": "tray.full", "ic_cfg_replace": "arrow.2.squarepath",
        "ic_cfg_theme": "paintpalette", "ic_cfg_backup": "externaldrive", "ic_cfg_other": "slider.horizontal.3",
        "ic_cfg_about": "info.circle"
    ]

    static func symbol(for androidName: String) -> String? { symbols[androidName] }
}

enum ComponentMetrics {
    static func badgeText(_ count: Int) -> String? {
        count <= 0 ? nil : count > 99 ? "99+" : String(count)
    }

    static func progress(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }

    static func flowFrames(sizes: [CGSize], width: CGFloat, spacing: CGFloat = 6) -> [CGRect] {
        let available = width.isFinite ? max(0, width) : CGFloat.greatestFiniteMagnitude
        let gap = spacing.isFinite ? max(0, spacing) : 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        return sizes.map { size in
            let itemWidth = size.width.isFinite ? max(0, size.width) : 0
            let itemHeight = size.height.isFinite ? max(0, size.height) : 0
            if x > 0, x + itemWidth > available { x = 0; y += rowHeight + gap; rowHeight = 0 }
            let frame = CGRect(x: x, y: y, width: itemWidth, height: itemHeight)
            x += itemWidth + gap
            rowHeight = max(rowHeight, itemHeight)
            return frame
        }
    }
}
