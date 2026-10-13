import Foundation
import SenseDraftCore

enum WritingPreferencesStore {
    private static let key = "writingPreferences"

    static func load() -> WritingPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(WritingPreferences.self, from: data) else {
            return WritingPreferences()
        }
        return value
    }

    static func save(_ value: WritingPreferences) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
