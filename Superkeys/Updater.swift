import Combine
import Foundation
import Sparkle

/// Checks superkeys.space for new versions and installs them in place.
///
/// Superkeys downloads updates itself, so macOS doesn't mark them as
/// downloaded from the internet and there's no Gatekeeper prompt. Every
/// release is signed with the same certificate, so the Accessibility grant
/// carries over, and each update is verified against the EdDSA public key in
/// Info.plist before it's installed.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    @Published private(set) var canCheckForUpdates = false
    @Published var checksAutomatically: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    /// Development builds never update themselves into a release.
    static let isEnabled: Bool = {
        #if DEBUG
        false
        #else
        true
        #endif
    }()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.isEnabled, updaterDelegate: nil, userDriverDelegate: nil)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        #if DEBUG
        return "\(short) (development)"
        #else
        return short
        #endif
    }
}
