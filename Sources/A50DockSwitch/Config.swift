import Foundation

struct AppConfig: Codable {
    var interval: Double = 1.0
    var debounce: Int = 1
    var paused: Bool = false
    var notifications: Bool = true
    var dockedUID: String = ""
    var dockedName: String = ""
    var undockedUID: String = ""
    var undockedName: String = ""
}

final class Config {
    static let shared = Config()

    private let url: URL
    private(set) var data: AppConfig = AppConfig()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("A50DockSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
        load()
    }

    func load() {
        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: raw) {
            data = decoded
        }
    }

    func save() {
        let tmp = url.appendingPathExtension("tmp")
        if let raw = try? JSONEncoder().encode(data) {
            try? raw.write(to: tmp)
            let _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        }
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        mutate(&data)
        save()
    }
}
