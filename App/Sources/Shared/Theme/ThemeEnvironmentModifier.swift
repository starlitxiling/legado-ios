import SwiftUI

struct EInkModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.transaction {
            if enabled { $0.animation = nil; $0.disablesAnimations = true }
        }
        .scrollBounceBehavior(enabled ? .basedOnSize : .automatic, axes: [.vertical, .horizontal])
        .onAppear { EInkMotion.apply(enabled: enabled) }
        .onChange(of: enabled) { _, value in EInkMotion.apply(enabled: value) }
    }
}

/// UIKit drives navigation pushes, sheet presentations and switch toggles outside SwiftUI transactions;
/// e-ink screens show each change once, so the global UIView animation flag follows the theme.
@MainActor enum EInkMotion {
    static var setAnimationsEnabled: (Bool) -> Void = { UIView.setAnimationsEnabled($0) }
    static func apply(enabled: Bool) {
        setAnimationsEnabled(!enabled)
    }
}


@MainActor struct ThemeEnvironmentModifier: ViewModifier {
    @State private var readerDarkIcons: Bool?
    @State private var readerHidesStatusBar: Bool?
    @State private var hostedPhase: ScenePhase?
    @Environment(\.scenePhase) private var scenePhase
    let store: ThemeStore
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let palette = store.palette(systemIsNight: systemScheme == .dark)
        let colors = ThemeColors(palette: palette)
        let appearance = ReaderStatusAppearance(mode: store.mode, palette: palette, darkIcons: readerDarkIcons)
        content
            .environment(\.scenePhase, hostedPhase ?? scenePhase)
            .environment(store)
            .environment(\.themeColors, colors)
            .tint(colors.accent)
            .foregroundStyle(colors.textPrimary)
            .background(colors.background.ignoresSafeArea())
            .preferredColorScheme(appearance.colorScheme)
            .background(ReaderStatusBarBridge(darkIcons: appearance.darkStatusIcons, hidesStatusBar: readerHidesStatusBar, colorScheme: appearance.colorScheme, phaseChanged: { hostedPhase = $0 }).frame(width: 0, height: 0))
            .onPreferenceChange(ReaderStatusIconPreference.self) { readerDarkIcons = $0 }
            .onPreferenceChange(ReaderStatusHiddenPreference.self) { readerHidesStatusBar = $0 }
            .saturation(palette.isEInk ? 0 : 1)
            .modifier(EInkModifier(enabled: palette.isEInk))
            .onReceive(NotificationCenter.default.publisher(for: BackupViewModel.restoredNotification)) { _ in store.preferences.reload() }
    }
}


/// Presented content is hosted outside the root view, so the e-ink grayscale must be applied to it directly.
struct EInkSheetContent: ViewModifier {
    @Environment(\.themeColors) private var colors
    func body(content: Content) -> some View { content.saturation(colors.isEInk ? 0 : 1) }
}

struct ThemeNavigationModifier: ViewModifier {
    @Environment(\.themeColors) private var colors
    func body(content: Content) -> some View {
        content
            .tint(colors.accent)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .toolbarBackground(colors.primary, for: .navigationBar)
            .toolbarBackground(colors.bottomBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar, .navigationBar)
            .toolbarColorScheme(colors.palette.primary.isDark ? .dark : .light, for: .navigationBar)
            // Sheets are hosted outside the root view, so the root `.saturation(0)` does not reach them.
            .saturation(colors.isEInk ? 0 : 1)
    }
}

extension View {
    func legadoNavigationTitle<S: StringProtocol>(_ title: S) -> some View {
        navigationTitle(title).modifier(ThemeNavigationModifier())
    }
    func legadoNavigationTitle(_ title: Text) -> some View {
        navigationTitle(title).modifier(ThemeNavigationModifier())
    }
}

struct ReaderStatusHiddenPreference: PreferenceKey {
    static let defaultValue: Bool? = nil
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) { value = nextValue() ?? value }
}

struct ReaderStatusIconPreference: PreferenceKey {
    static var defaultValue: Bool? { nil }
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        if let next = nextValue() { value = next }
    }
}
