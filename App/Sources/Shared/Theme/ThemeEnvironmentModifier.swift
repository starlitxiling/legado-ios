import SwiftUI

struct EInkModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.transaction {
            if enabled { $0.animation = nil; $0.disablesAnimations = true }
        }
    }
}

@MainActor struct ThemeEnvironmentModifier: ViewModifier {
    let store: ThemeStore
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let palette = store.palette(systemIsNight: systemScheme == .dark)
        let colors = ThemeColors(palette: palette)
        content
            .environment(store)
            .environment(\.themeColors, colors)
            .tint(colors.accent)
            .foregroundStyle(colors.textPrimary)
            .background(colors.background.ignoresSafeArea())
            .preferredColorScheme(store.mode == .system ? nil : palette.isNight ? .dark : .light)
            .saturation(palette.isEInk ? 0 : 1)
            .modifier(EInkModifier(enabled: palette.isEInk))
            .onReceive(NotificationCenter.default.publisher(for: BackupViewModel.restoredNotification)) { _ in store.preferences.reload() }
    }
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
