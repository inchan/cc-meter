import Foundation
import Combine

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings
    private let store: SettingsStoreProtocol

    init(store: SettingsStoreProtocol = SettingsStore()) {
        self.store = store
        self.settings = store.load()
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        do {
            try store.save(settings)
        } catch {
            Log.app.error("settings save failed: \(String(describing: error))")
        }
    }

    func setDisplayMode(_ mode: UsageDisplayMode) {
        update { $0.usageDisplayMode = mode }
    }
}
