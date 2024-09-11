import Foundation

class StorageManager {
    static let shared = StorageManager()

    private var storage: [String: Date] = [:] {
        didSet {
            saveStorage()
        }
    }

    private var storageURL: URL {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentDirectory.appendingPathComponent("AssetSeenTimes.json")
    }

    init() {
        loadStorage()
    }

    func storeOrUpdateAssetSeenTime(assetId: String) {
        storage[assetId] = Date()
    }

    func getLastSeenTime(assetId: String?) -> Date? {
        guard let assetId = assetId else {
            return nil
        }
        return storage[assetId]
    }

    private func loadStorage() {
        do {
            let data = try Data(contentsOf: storageURL)
            storage = try JSONDecoder().decode([String: Date].self, from: data)
        } catch {
            print("Error loading storage: \(error)")
        }
    }

    private func saveStorage() {
        do {
            let data = try JSONEncoder().encode(storage)
            try data.write(to: storageURL, options: [.atomicWrite])
        } catch {
            print("Error saving storage: \(error)")
        }
    }
}
