import AVFoundation
import Combine
import Foundation

struct WebSearchProvider: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let baseURL: String

    init(name: String, baseURL: String) {
        self.id = name
        self.name = name
        self.baseURL = baseURL
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let recentFilePaths = "FrieveEditorMac.recentFilePaths"
        static let autoSaveDefault = "FrieveEditorMac.autoSaveDefault"
        static let autoReloadDefault = "FrieveEditorMac.autoReloadDefault"
        static let autoSaveMinIntervalSec = "FrieveEditorMac.autoSaveMinIntervalSec"
        static let autoSaveIdleSec = "FrieveEditorMac.autoSaveIdleSec"
        static let autoReloadPollSec = "FrieveEditorMac.autoReloadPollSec"
        static let preferredWebSearchName = "FrieveEditorMac.preferredWebSearchName"
        static let gptAPIKey = "FrieveEditorMac.gptAPIKey"
        static let gptModel = "FrieveEditorMac.gptModel"
        static let gptSystemPrompt = "FrieveEditorMac.gptSystemPrompt"
        static let readAloudRate = "FrieveEditorMac.readAloudRate"
        static let language = "FrieveEditorMac.language"
        static let animationVisibleCardCount = "FrieveEditorMac.animationVisibleCardCount"
        static let animationSpeed = "FrieveEditorMac.animationSpeed"
        static let animationPaused = "FrieveEditorMac.animationPaused"
        static let showOverview = "FrieveEditorMac.showOverview"
        static let showFileList = "FrieveEditorMac.showFileList"
        static let showCardList = "FrieveEditorMac.showCardList"
        static let showInspector = "FrieveEditorMac.showInspector"
        static let showStatusBar = "FrieveEditorMac.showStatusBar"
    }

    private let userDefaults: UserDefaults
    private var isBootstrapping = true

    let webSearchProviders: [WebSearchProvider]

    @Published var recentFilePaths: [String] {
        didSet { persistIfReady() }
    }

    @Published var autoSaveDefault: Bool {
        didSet { persistIfReady() }
    }

    @Published var autoReloadDefault: Bool {
        didSet { persistIfReady() }
    }

    @Published var autoSaveMinIntervalSec: Int {
        didSet { persistIfReady() }
    }

    @Published var autoSaveIdleSec: Int {
        didSet { persistIfReady() }
    }

    @Published var autoReloadPollSec: Int {
        didSet { persistIfReady() }
    }

    @Published var preferredWebSearchName: String {
        didSet { persistIfReady() }
    }

    @Published var gptAPIKey: String {
        didSet { persistIfReady() }
    }

    @Published var gptModel: String {
        didSet { persistIfReady() }
    }

    @Published var gptSystemPrompt: String {
        didSet { persistIfReady() }
    }

    @Published var readAloudRate: Int {
        didSet {
            let normalized = Self.normalizedReadAloudRate(from: readAloudRate)
            guard normalized == readAloudRate else {
                readAloudRate = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var language: String {
        didSet { persistIfReady() }
    }

    @Published var animationVisibleCardCount: Int {
        didSet { persistIfReady() }
    }

    @Published var animationSpeed: Int {
        didSet { persistIfReady() }
    }

    @Published var animationPaused: Bool {
        didSet { persistIfReady() }
    }

    @Published var showOverview: Bool {
        didSet { persistIfReady() }
    }

    @Published var showFileList: Bool {
        didSet { persistIfReady() }
    }

    @Published var showCardList: Bool {
        didSet { persistIfReady() }
    }

    @Published var showInspector: Bool {
        didSet { persistIfReady() }
    }

    @Published var showStatusBar: Bool {
        didSet { persistIfReady() }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let providers = [
            WebSearchProvider(name: "Google", baseURL: "https://www.google.com/search?q="),
            WebSearchProvider(name: "DuckDuckGo", baseURL: "https://duckduckgo.com/?q="),
            WebSearchProvider(name: "Wikipedia", baseURL: "https://en.wikipedia.org/w/index.php?search=")
        ]
        webSearchProviders = providers

        recentFilePaths = userDefaults.stringArray(forKey: Keys.recentFilePaths) ?? []
        autoSaveDefault = userDefaults.object(forKey: Keys.autoSaveDefault) as? Bool ?? true
        autoReloadDefault = userDefaults.object(forKey: Keys.autoReloadDefault) as? Bool ?? true
        autoSaveMinIntervalSec = userDefaults.object(forKey: Keys.autoSaveMinIntervalSec) as? Int ?? 60
        autoSaveIdleSec = userDefaults.object(forKey: Keys.autoSaveIdleSec) as? Int ?? 3
        autoReloadPollSec = userDefaults.object(forKey: Keys.autoReloadPollSec) as? Int ?? 2
        preferredWebSearchName = userDefaults.string(forKey: Keys.preferredWebSearchName) ?? providers.first?.name ?? "Google"
        gptAPIKey = userDefaults.string(forKey: Keys.gptAPIKey) ?? ""
        gptModel = userDefaults.string(forKey: Keys.gptModel) ?? "gpt-4.1"
        gptSystemPrompt = userDefaults.string(forKey: Keys.gptSystemPrompt) ?? "Summarize the selected card, suggest related cards, and propose next writing steps."
        readAloudRate = Self.normalizedReadAloudRate(from: userDefaults.object(forKey: Keys.readAloudRate))
        language = userDefaults.string(forKey: Keys.language) ?? "English"
        animationVisibleCardCount = userDefaults.object(forKey: Keys.animationVisibleCardCount) as? Int ?? 10
        animationSpeed = userDefaults.object(forKey: Keys.animationSpeed) as? Int ?? 30
        animationPaused = userDefaults.object(forKey: Keys.animationPaused) as? Bool ?? false
        showOverview = userDefaults.object(forKey: Keys.showOverview) as? Bool ?? true
        showFileList = userDefaults.object(forKey: Keys.showFileList) as? Bool ?? true
        showCardList = userDefaults.object(forKey: Keys.showCardList) as? Bool ?? true
        showInspector = userDefaults.object(forKey: Keys.showInspector) as? Bool ?? true
        showStatusBar = userDefaults.object(forKey: Keys.showStatusBar) as? Bool ?? true
        isBootstrapping = false
        persist()
    }

    var recentFiles: [URL] {
        recentFilePaths.map { URL(fileURLWithPath: $0) }
    }

    func recordRecent(url: URL) {
        recentFilePaths.removeAll { $0 == url.path }
        recentFilePaths.insert(url.path, at: 0)
        recentFilePaths = Array(recentFilePaths.prefix(10))
    }

    func preferredWebSearchProvider() -> WebSearchProvider {
        webSearchProviders.first { $0.name == preferredWebSearchName } ?? webSearchProviders[0]
    }

    func preferredWebSearchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: preferredWebSearchProvider().baseURL + encoded)
    }

    var readAloudSpeechRate: Float {
        let defaultRate = AVSpeechUtteranceDefaultSpeechRate
        let adjustedRate = defaultRate + Float(readAloudRate) * 0.02
        return min(max(adjustedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private func persistIfReady() {
        guard !isBootstrapping else { return }
        persist()
    }

    private func persist() {
        userDefaults.set(recentFilePaths, forKey: Keys.recentFilePaths)
        userDefaults.set(autoSaveDefault, forKey: Keys.autoSaveDefault)
        userDefaults.set(autoReloadDefault, forKey: Keys.autoReloadDefault)
        userDefaults.set(autoSaveMinIntervalSec, forKey: Keys.autoSaveMinIntervalSec)
        userDefaults.set(autoSaveIdleSec, forKey: Keys.autoSaveIdleSec)
        userDefaults.set(autoReloadPollSec, forKey: Keys.autoReloadPollSec)
        userDefaults.set(preferredWebSearchName, forKey: Keys.preferredWebSearchName)
        userDefaults.set(gptAPIKey, forKey: Keys.gptAPIKey)
        userDefaults.set(gptModel, forKey: Keys.gptModel)
        userDefaults.set(gptSystemPrompt, forKey: Keys.gptSystemPrompt)
        userDefaults.set(readAloudRate, forKey: Keys.readAloudRate)
        userDefaults.set(language, forKey: Keys.language)
        userDefaults.set(animationVisibleCardCount, forKey: Keys.animationVisibleCardCount)
        userDefaults.set(animationSpeed, forKey: Keys.animationSpeed)
        userDefaults.set(animationPaused, forKey: Keys.animationPaused)
        userDefaults.set(showOverview, forKey: Keys.showOverview)
        userDefaults.set(showFileList, forKey: Keys.showFileList)
        userDefaults.set(showCardList, forKey: Keys.showCardList)
        userDefaults.set(showInspector, forKey: Keys.showInspector)
        userDefaults.set(showStatusBar, forKey: Keys.showStatusBar)
    }

    private static func normalizedReadAloudRate(from storedValue: Any?) -> Int {
        let numericValue: Double
        switch storedValue {
        case let value as Int:
            numericValue = Double(value)
        case let value as Double:
            numericValue = value
        case let value as NSNumber:
            numericValue = value.doubleValue
        case let value as String:
            guard let parsed = Double(value) else { return 0 }
            numericValue = parsed
        default:
            return 0
        }

        let roundedValue = Int(numericValue.rounded())
        if (-10 ... 10).contains(roundedValue), numericValue == Double(roundedValue) {
            return roundedValue
        }

        if (100 ... 320).contains(roundedValue) {
            let migratedValue = Int(((numericValue - 175.0) / 7.5).rounded())
            return min(max(migratedValue, -10), 10)
        }

        return min(max(roundedValue, -10), 10)
    }
}
