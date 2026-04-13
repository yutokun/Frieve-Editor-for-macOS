import AVFoundation
import Combine
import Foundation

enum BrowserInlineEditorPosition: Int, CaseIterable, Identifiable {
    case underCard = 0
    case browserRight = 1
    case browserBottom = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .underCard:
            "Under Card"
        case .browserRight:
            "Browser Right"
        case .browserBottom:
            "Browser Bottom"
        }
    }
}

enum BrowserScoreDisplayType: Int, CaseIterable, Identifiable {
    case authenticity = 0
    case startingPoint = 1
    case destination = 2
    case linksOut = 3
    case linksIn = 4
    case linksTotal = 5
    case linksInOut = 6
    case textLength = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .authenticity:
            "Authenticity"
        case .startingPoint:
            "Starting Point"
        case .destination:
            "Destination"
        case .linksOut:
            "Links (Out)"
        case .linksIn:
            "Links (In)"
        case .linksTotal:
            "Links (Total)"
        case .linksInOut:
            "Links (In-Out)"
        case .textLength:
            "Text Length"
        }
    }
}

enum BrowserBackgroundAnimationType: Int, CaseIterable, Identifiable {
    case flowingLines = 0
    case bubbles = 1
    case snow = 2
    case petals = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .flowingLines:
            "Flowing Lines"
        case .bubbles:
            "Bubbles"
        case .snow:
            "Snow"
        case .petals:
            "Petals"
        }
    }
}

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
        static let browserCardShadow = "FrieveEditorMac.browserCardShadow"
        static let browserCardGradation = "FrieveEditorMac.browserCardGradation"
        static let browserTickerVisible = "FrieveEditorMac.browserTickerVisible"
        static let browserTickerLines = "FrieveEditorMac.browserTickerLines"
        static let browserImageVisible = "FrieveEditorMac.browserImageVisible"
        static let browserVideoVisible = "FrieveEditorMac.browserVideoVisible"
        static let browserDrawingVisible = "FrieveEditorMac.browserDrawingVisible"
        static let browserImageLimitation = "FrieveEditorMac.browserImageLimitation"
        static let browserLinkVisible = "FrieveEditorMac.browserLinkVisible"
        static let browserLinkHemming = "FrieveEditorMac.browserLinkHemming"
        static let browserLinkDirectionVisible = "FrieveEditorMac.browserLinkDirectionVisible"
        static let browserLinkNameVisible = "FrieveEditorMac.browserLinkNameVisible"
        static let browserLabelCircleVisible = "FrieveEditorMac.browserLabelCircleVisible"
        static let browserLabelRectangleVisible = "FrieveEditorMac.browserLabelRectangleVisible"
        static let browserLabelNameVisible = "FrieveEditorMac.browserLabelNameVisible"
        static let browserTextVisible = "FrieveEditorMac.browserTextVisible"
        static let browserTextCentering = "FrieveEditorMac.browserTextCentering"
        static let browserTextWordWrap = "FrieveEditorMac.browserTextWordWrap"
        static let browserEditInBrowser = "FrieveEditorMac.browserEditInBrowser"
        static let browserEditInBrowserAlways = "FrieveEditorMac.browserEditInBrowserAlways"
        static let browserEditInBrowserPosition = "FrieveEditorMac.browserEditInBrowserPosition"
        static let browserScoreVisible = "FrieveEditorMac.browserScoreVisible"
        static let browserScoreType = "FrieveEditorMac.browserScoreType"
        static let browserFontFamily = "FrieveEditorMac.browserFontFamily"
        static let browserFontSize = "FrieveEditorMac.browserFontSize"
        static let browserWallpaperPath = "FrieveEditorMac.browserWallpaperPath"
        static let browserWallpaperFixed = "FrieveEditorMac.browserWallpaperFixed"
        static let browserWallpaperTiled = "FrieveEditorMac.browserWallpaperTiled"
        static let browserBackgroundAnimation = "FrieveEditorMac.browserBackgroundAnimation"
        static let browserBackgroundAnimationType = "FrieveEditorMac.browserBackgroundAnimationType"
        static let browserCursorAnimation = "FrieveEditorMac.browserCursorAnimation"
        static let browserNoScrollLag = "FrieveEditorMac.browserNoScrollLag"
        static let browserAntialiasingEnabled = "FrieveEditorMac.browserAntialiasingEnabled"
        static let browserAntialiasingSampleCount = "FrieveEditorMac.browserAntialiasingSampleCount"
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

    @Published var browserCardShadow: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserCardGradation: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserTickerVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserTickerLines: Int {
        didSet {
            let normalized = min(max(browserTickerLines, 1), 2)
            guard normalized == browserTickerLines else {
                browserTickerLines = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var browserImageVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserVideoVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserDrawingVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserImageLimitation: Int {
        didSet {
            let normalized = Self.normalizedBrowserImageLimitation(from: browserImageLimitation)
            guard normalized == browserImageLimitation else {
                browserImageLimitation = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var browserLinkVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserLinkHemming: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserLinkDirectionVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserLinkNameVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserLabelCircleVisible: Bool {
        didSet {
            if browserLabelCircleVisible && browserLabelRectangleVisible {
                browserLabelRectangleVisible = false
                return
            }
            persistIfReady()
        }
    }

    @Published var browserLabelRectangleVisible: Bool {
        didSet {
            if browserLabelRectangleVisible && browserLabelCircleVisible {
                browserLabelCircleVisible = false
                return
            }
            persistIfReady()
        }
    }

    @Published var browserLabelNameVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserTextVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserTextCentering: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserTextWordWrap: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserEditInBrowser: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserEditInBrowserAlways: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserEditInBrowserPosition: Int {
        didSet {
            let normalized = min(max(browserEditInBrowserPosition, 0), 2)
            guard normalized == browserEditInBrowserPosition else {
                browserEditInBrowserPosition = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var browserScoreVisible: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserScoreType: Int {
        didSet {
            let normalized = min(max(browserScoreType, 0), 7)
            guard normalized == browserScoreType else {
                browserScoreType = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var browserFontFamily: String {
        didSet {
            let normalized = browserFontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == browserFontFamily else {
                browserFontFamily = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var browserFontSize: Int {
        didSet {
            let normalized = Self.normalizedBrowserFontSize(from: browserFontSize)
            guard normalized == browserFontSize else {
                browserFontSize = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var browserWallpaperPath: String {
        didSet { persistIfReady() }
    }

    @Published var browserWallpaperFixed: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserWallpaperTiled: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserBackgroundAnimation: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserBackgroundAnimationType: Int {
        didSet {
            let normalized = min(max(browserBackgroundAnimationType, 0), 3)
            guard normalized == browserBackgroundAnimationType else {
                browserBackgroundAnimationType = normalized
                return
            }
            persistIfReady()
        }
    }

    @Published var browserCursorAnimation: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserNoScrollLag: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserAntialiasingEnabled: Bool {
        didSet { persistIfReady() }
    }

    @Published var browserAntialiasingSampleCount: Int {
        didSet {
            let normalized = Self.normalizedBrowserAntialiasingSampleCount(from: browserAntialiasingSampleCount)
            guard normalized == browserAntialiasingSampleCount else {
                browserAntialiasingSampleCount = normalized
                return
            }
            persistIfReady()
        }
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
        browserCardShadow = userDefaults.object(forKey: Keys.browserCardShadow) as? Bool ?? true
        browserCardGradation = userDefaults.object(forKey: Keys.browserCardGradation) as? Bool ?? true
        browserTickerVisible = userDefaults.object(forKey: Keys.browserTickerVisible) as? Bool ?? false
        browserTickerLines = min(max(userDefaults.object(forKey: Keys.browserTickerLines) as? Int ?? 1, 1), 2)
        browserImageVisible = userDefaults.object(forKey: Keys.browserImageVisible) as? Bool ?? true
        browserVideoVisible = userDefaults.object(forKey: Keys.browserVideoVisible) as? Bool ?? true
        browserDrawingVisible = userDefaults.object(forKey: Keys.browserDrawingVisible) as? Bool ?? true
        browserImageLimitation = Self.normalizedBrowserImageLimitation(from: userDefaults.object(forKey: Keys.browserImageLimitation))
        browserLinkVisible = userDefaults.object(forKey: Keys.browserLinkVisible) as? Bool ?? true
        browserLinkHemming = userDefaults.object(forKey: Keys.browserLinkHemming) as? Bool ?? false
        browserLinkDirectionVisible = userDefaults.object(forKey: Keys.browserLinkDirectionVisible) as? Bool ?? true
        browserLinkNameVisible = userDefaults.object(forKey: Keys.browserLinkNameVisible) as? Bool ?? true
        let storedBrowserLabelCircleVisible = userDefaults.object(forKey: Keys.browserLabelCircleVisible) as? Bool ?? false
        let storedBrowserLabelRectangleVisible = userDefaults.object(forKey: Keys.browserLabelRectangleVisible) as? Bool ?? true
        browserLabelCircleVisible = storedBrowserLabelCircleVisible && !storedBrowserLabelRectangleVisible
        browserLabelRectangleVisible = storedBrowserLabelRectangleVisible
        browserLabelNameVisible = userDefaults.object(forKey: Keys.browserLabelNameVisible) as? Bool ?? true
        browserTextVisible = userDefaults.object(forKey: Keys.browserTextVisible) as? Bool ?? true
        browserTextCentering = userDefaults.object(forKey: Keys.browserTextCentering) as? Bool ?? false
        browserTextWordWrap = userDefaults.object(forKey: Keys.browserTextWordWrap) as? Bool ?? true
        browserEditInBrowser = userDefaults.object(forKey: Keys.browserEditInBrowser) as? Bool ?? true
        browserEditInBrowserAlways = userDefaults.object(forKey: Keys.browserEditInBrowserAlways) as? Bool ?? false
        browserEditInBrowserPosition = min(max(userDefaults.object(forKey: Keys.browserEditInBrowserPosition) as? Int ?? 0, 0), 2)
        browserScoreVisible = userDefaults.object(forKey: Keys.browserScoreVisible) as? Bool ?? false
        browserScoreType = min(max(userDefaults.object(forKey: Keys.browserScoreType) as? Int ?? 0, 0), 7)
        browserFontFamily = userDefaults.string(forKey: Keys.browserFontFamily)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        browserFontSize = Self.normalizedBrowserFontSize(from: userDefaults.object(forKey: Keys.browserFontSize))
        browserWallpaperPath = userDefaults.string(forKey: Keys.browserWallpaperPath) ?? ""
        browserWallpaperFixed = userDefaults.object(forKey: Keys.browserWallpaperFixed) as? Bool ?? true
        browserWallpaperTiled = userDefaults.object(forKey: Keys.browserWallpaperTiled) as? Bool ?? false
        browserBackgroundAnimation = userDefaults.object(forKey: Keys.browserBackgroundAnimation) as? Bool ?? false
        browserBackgroundAnimationType = min(max(userDefaults.object(forKey: Keys.browserBackgroundAnimationType) as? Int ?? 0, 0), 3)
        browserCursorAnimation = userDefaults.object(forKey: Keys.browserCursorAnimation) as? Bool ?? true
        browserNoScrollLag = userDefaults.object(forKey: Keys.browserNoScrollLag) as? Bool ?? true
        browserAntialiasingEnabled = userDefaults.object(forKey: Keys.browserAntialiasingEnabled) as? Bool ?? false
        browserAntialiasingSampleCount = Self.normalizedBrowserAntialiasingSampleCount(
            from: userDefaults.object(forKey: Keys.browserAntialiasingSampleCount)
        )
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
        userDefaults.set(browserCardShadow, forKey: Keys.browserCardShadow)
        userDefaults.set(browserCardGradation, forKey: Keys.browserCardGradation)
        userDefaults.set(browserTickerVisible, forKey: Keys.browserTickerVisible)
        userDefaults.set(browserTickerLines, forKey: Keys.browserTickerLines)
        userDefaults.set(browserImageVisible, forKey: Keys.browserImageVisible)
        userDefaults.set(browserVideoVisible, forKey: Keys.browserVideoVisible)
        userDefaults.set(browserDrawingVisible, forKey: Keys.browserDrawingVisible)
        userDefaults.set(browserImageLimitation, forKey: Keys.browserImageLimitation)
        userDefaults.set(browserLinkVisible, forKey: Keys.browserLinkVisible)
        userDefaults.set(browserLinkHemming, forKey: Keys.browserLinkHemming)
        userDefaults.set(browserLinkDirectionVisible, forKey: Keys.browserLinkDirectionVisible)
        userDefaults.set(browserLinkNameVisible, forKey: Keys.browserLinkNameVisible)
        userDefaults.set(browserLabelCircleVisible, forKey: Keys.browserLabelCircleVisible)
        userDefaults.set(browserLabelRectangleVisible, forKey: Keys.browserLabelRectangleVisible)
        userDefaults.set(browserLabelNameVisible, forKey: Keys.browserLabelNameVisible)
        userDefaults.set(browserTextVisible, forKey: Keys.browserTextVisible)
        userDefaults.set(browserTextCentering, forKey: Keys.browserTextCentering)
        userDefaults.set(browserTextWordWrap, forKey: Keys.browserTextWordWrap)
        userDefaults.set(browserEditInBrowser, forKey: Keys.browserEditInBrowser)
        userDefaults.set(browserEditInBrowserAlways, forKey: Keys.browserEditInBrowserAlways)
        userDefaults.set(browserEditInBrowserPosition, forKey: Keys.browserEditInBrowserPosition)
        userDefaults.set(browserScoreVisible, forKey: Keys.browserScoreVisible)
        userDefaults.set(browserScoreType, forKey: Keys.browserScoreType)
        userDefaults.set(browserFontFamily, forKey: Keys.browserFontFamily)
        userDefaults.set(browserFontSize, forKey: Keys.browserFontSize)
        userDefaults.set(browserWallpaperPath, forKey: Keys.browserWallpaperPath)
        userDefaults.set(browserWallpaperFixed, forKey: Keys.browserWallpaperFixed)
        userDefaults.set(browserWallpaperTiled, forKey: Keys.browserWallpaperTiled)
        userDefaults.set(browserBackgroundAnimation, forKey: Keys.browserBackgroundAnimation)
        userDefaults.set(browserBackgroundAnimationType, forKey: Keys.browserBackgroundAnimationType)
        userDefaults.set(browserCursorAnimation, forKey: Keys.browserCursorAnimation)
        userDefaults.set(browserNoScrollLag, forKey: Keys.browserNoScrollLag)
        userDefaults.set(browserAntialiasingEnabled, forKey: Keys.browserAntialiasingEnabled)
        userDefaults.set(browserAntialiasingSampleCount, forKey: Keys.browserAntialiasingSampleCount)
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

    private static func normalizedBrowserImageLimitation(from storedValue: Any?) -> Int {
        let allowedValues = [32, 40, 64, 80, 120, 160, 240, 320]
        let numericValue: Int
        switch storedValue {
        case let value as Int:
            numericValue = value
        case let value as Double:
            numericValue = Int(value.rounded())
        case let value as NSNumber:
            numericValue = value.intValue
        case let value as String:
            guard let parsed = Int(value) else { return 80 }
            numericValue = parsed
        default:
            return 80
        }

        return allowedValues.min(by: { abs($0 - numericValue) < abs($1 - numericValue) }) ?? 80
    }

    private static func normalizedBrowserFontSize(from storedValue: Any?) -> Int {
        let numericValue: Int
        switch storedValue {
        case let value as Int:
            numericValue = value
        case let value as Double:
            numericValue = Int(value.rounded())
        case let value as NSNumber:
            numericValue = value.intValue
        case let value as String:
            guard let parsed = Int(value) else { return 13 }
            numericValue = parsed
        default:
            return 13
        }
        return min(max(numericValue, 8), 36)
    }

    private static func normalizedBrowserAntialiasingSampleCount(from storedValue: Any?) -> Int {
        let numericValue: Int
        switch storedValue {
        case let value as Int:
            numericValue = value
        case let value as Double:
            numericValue = Int(value.rounded())
        case let value as NSNumber:
            numericValue = value.intValue
        case let value as String:
            guard let parsed = Int(value) else { return 2 }
            numericValue = parsed
        default:
            return 2
        }
        return numericValue == 4 ? 4 : 2
    }
}
