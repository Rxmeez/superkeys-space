import AppKit

struct BoundApp: Codable, Equatable, Identifiable {
    var keyCode: Int
    var label: String
    var bundleID: String
    var name: String
    var id: String { String(keyCode) }
}

@MainActor
final class BindingsStore: ObservableObject {
    static let shared = BindingsStore()

    private static let defaultsKey = "bindings.v2"

    @Published private(set) var bindings: [BoundApp]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([BoundApp].self, from: data) {
            bindings = decoded
        } else {
            bindings = []
        }
        syncTap()
    }

    func app(forKeyCode keyCode: Int) -> BoundApp? {
        bindings.first { $0.keyCode == keyCode }
    }

    /// Returns an error message, or nil on success.
    func add(keyCode: Int, label: String, bundleID: String, name: String) -> String? {
        if let error = validate(keyCode: keyCode, replacing: nil) { return error }
        bindings.append(BoundApp(keyCode: keyCode, label: label, bundleID: bundleID, name: name))
        commit()
        return nil
    }

    func setKey(of app: BoundApp, keyCode: Int, label: String) -> String? {
        if let error = validate(keyCode: keyCode, replacing: app.id) { return error }
        guard let index = bindings.firstIndex(where: { $0.id == app.id }) else { return nil }
        bindings[index].keyCode = keyCode
        bindings[index].label = label
        commit()
        return nil
    }

    func replaceAll(with apps: [BoundApp]) {
        bindings = apps
        commit()
    }

    func remove(_ app: BoundApp) {
        bindings.removeAll { $0.id == app.id }
        commit()
    }

    /// Returns a reason the key cannot be used, or nil when it is free.
    func validate(keyCode: Int, replacing id: String?) -> String? {
        switch Int64(keyCode) {
        case let code where KeyCodes.windowKeys.contains(code):
            return "\(Glyph.hyper) with the arrows and Return moves windows."
        case KeyCodes.capsLock, KeyCodes.hyperF18:
            return "That's the Hyper Key itself."
        case KeyCodes.mehF19:
            return "That's the Meh Key."
        default:
            break
        }
        if let existing = bindings.first(where: { $0.keyCode == keyCode && $0.id != id }) {
            return "\(Glyph.hyper) \(existing.label) already opens \(existing.name)."
        }
        return nil
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        syncTap()
    }

    private func syncTap() {
        HyperEventTap.shared.setAppKeyCodes(Set(bindings.map { Int64($0.keyCode) }))
    }
}
