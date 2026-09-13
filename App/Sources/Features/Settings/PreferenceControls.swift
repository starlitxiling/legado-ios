import SwiftUI
import LegadoCore

@MainActor
struct PreferenceControls {
    let preferences: AppPreferences
    func string(_ key: String) -> Binding<String> {
        Binding(get: { preferences.string(key) }, set: { preferences.set(key, .string($0)) })
    }
    func boolean(_ key: String) -> Binding<Bool> {
        Binding(get: { preferences.boolean(key) }, set: { preferences.set(key, .boolean($0)) })
    }
    func integer(_ key: String) -> Binding<Int> {
        Binding(get: { preferences.integer(key) }, set: { preferences.set(key, .int(Int32(clamping: $0))) })
    }
    func toggle(_ title: String, _ key: String) -> some View { Toggle(title, isOn: boolean(key)) }
    func number(_ title: String, _ key: String, range: ClosedRange<Int>) -> some View {
        Stepper("\(title)：\(preferences.integer(key))", value: integer(key), in: range)
    }
    func text(_ title: String, _ key: String) -> some View {
        TextField(title, text: string(key)).textInputAutocapitalization(.never).autocorrectionDisabled()
    }
}
