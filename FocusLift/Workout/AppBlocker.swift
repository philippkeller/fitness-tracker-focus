import FamilyControls
import Foundation
import ManagedSettings
import Observation

/// Blocks distracting apps (X, Instagram, …) with a Screen Time shield while a workout runs.
/// Apps are picked by the user with Apple's picker; iOS only hands us opaque tokens.
@Observable
final class AppBlocker {
    static let enabledKey = "blockAppsDuringWorkout"
    private static let selectionKey = "blockedAppsSelection"

    private(set) var selection = FamilyActivitySelection()
    private(set) var isAuthorized = false
    var errorMessage: String?

    private let settingsStore = ManagedSettingsStore()

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
        refreshAuthorization()
    }

    func refreshAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await MainActor.run {
                self.errorMessage = nil
                self.refreshAuthorization()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.refreshAuthorization()
            }
        }
    }

    func setSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
        if let data = try? JSONEncoder().encode(newSelection) {
            UserDefaults.standard.set(data, forKey: Self.selectionKey)
        }
    }

    func block() {
        refreshAuthorization()
        guard isEnabled, isAuthorized, selectedCount > 0 else { return }
        settingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        settingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        settingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        settingsStore.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
    }

    func unblock() {
        settingsStore.clearAllSettings()
    }
}
