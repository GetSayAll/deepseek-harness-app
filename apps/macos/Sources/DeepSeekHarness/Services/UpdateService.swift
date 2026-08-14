import AppKit
import Combine
import Sparkle

struct UpdateFeedSelection {
    let stableFeedURLString: String?
    private(set) var previewFeedURL: URL?

    mutating func usePreviewFeed(_ url: URL) {
        previewFeedURL = url
    }

    mutating func useStableFeed() {
        previewFeedURL = nil
    }

    func feedURLString(includesPreviewUpdates: Bool) -> String? {
        if includesPreviewUpdates, let previewFeedURL {
            return previewFeedURL.absoluteString
        }
        return stableFeedURLString
    }
}

@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    private enum FeedError: Error {
        case invalidResponse
        case feedNotFound
    }

    private struct GitHubRelease: Decodable {
        let draft: Bool
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private static let previewPreferenceKey = "checksForPreviewUpdates"
    private static let releasesURL = URL(
        string: "https://api.github.com/repos/GetSayAll/deepseek-harness-app/releases?per_page=30"
    )!
    private static let previewFeedRefreshInterval: TimeInterval = 6 * 60 * 60

    @Published var checksForPreviewUpdates: Bool {
        didSet {
            guard checksForPreviewUpdates != oldValue else { return }
            UserDefaults.standard.set(checksForPreviewUpdates, forKey: Self.previewPreferenceKey)
            updatePreviewPreference()
        }
    }

    @Published private(set) var isResolvingPreviewFeed = false

    private var feedSelection: UpdateFeedSelection
    private var feedRefreshTask: Task<Void, Never>?
    private var feedRefreshTimer: Timer?
    private var updaterStarted = false
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        checksForPreviewUpdates = UserDefaults.standard.bool(forKey: Self.previewPreferenceKey)
        feedSelection = UpdateFeedSelection(
            stableFeedURLString: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        )
        super.init()
    }

    var isConfigured: Bool {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return feedSelection.stableFeedURLString?.isEmpty == false && publicKey?.isEmpty == false
    }

    var canCheckForUpdates: Bool {
        isConfigured && !isResolvingPreviewFeed
    }

    var channelLabel: String {
        checksForPreviewUpdates ? "正式版与预览版" : "仅正式版"
    }

    func start() {
        guard isConfigured, !updaterStarted else { return }
        configurePreviewFeedTimer()
        if checksForPreviewUpdates {
            refreshPreviewFeed(startUpdaterAfterRefresh: true)
        } else {
            startUpdaterIfNeeded()
        }
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        if checksForPreviewUpdates {
            refreshPreviewFeed(checkAfterRefresh: true)
        } else {
            feedSelection.useStableFeed()
            startUpdaterIfNeeded()
            updaterController.checkForUpdates(nil)
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedSelection.feedURLString(includesPreviewUpdates: checksForPreviewUpdates)
    }

    private func updatePreviewPreference() {
        feedRefreshTask?.cancel()
        isResolvingPreviewFeed = false
        feedSelection.useStableFeed()
        configurePreviewFeedTimer()
        guard isConfigured else { return }
        startUpdaterIfNeeded()
        if checksForPreviewUpdates {
            refreshPreviewFeed(resetUpdateCycleAfterRefresh: true)
        } else {
            updaterController.updater.resetUpdateCycleAfterShortDelay()
        }
    }

    private func configurePreviewFeedTimer() {
        feedRefreshTimer?.invalidate()
        feedRefreshTimer = nil
        guard checksForPreviewUpdates else { return }
        feedRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.previewFeedRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPreviewFeed(resetUpdateCycleAfterRefresh: true)
            }
        }
    }

    private func startUpdaterIfNeeded() {
        guard !updaterStarted else { return }
        updaterController.startUpdater()
        updaterStarted = true
    }

    private func refreshPreviewFeed(
        startUpdaterAfterRefresh: Bool = false,
        resetUpdateCycleAfterRefresh: Bool = false,
        checkAfterRefresh: Bool = false
    ) {
        feedRefreshTask?.cancel()
        isResolvingPreviewFeed = true
        feedRefreshTask = Task { [weak self] in
            guard let self else { return }
            let resolvedURL = try? await Self.latestReleaseFeedURL()
            guard !Task.isCancelled else { return }
            isResolvingPreviewFeed = false
            guard checksForPreviewUpdates else { return }
            if let resolvedURL {
                feedSelection.usePreviewFeed(resolvedURL)
            } else {
                feedSelection.useStableFeed()
            }
            if startUpdaterAfterRefresh {
                startUpdaterIfNeeded()
            }
            if resetUpdateCycleAfterRefresh, updaterStarted {
                updaterController.updater.resetUpdateCycleAfterShortDelay()
            }
            if checkAfterRefresh {
                startUpdaterIfNeeded()
                updaterController.checkForUpdates(nil)
            }
        }
    }

    private static func latestReleaseFeedURL() async throws -> URL {
        var request = URLRequest(url: releasesURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DS-Harness", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw FeedError.invalidResponse
        }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        guard let feedURL = releases.lazy
            .filter({ !$0.draft })
            .flatMap(\.assets)
            .first(where: { $0.name == "appcast.xml" })?
            .browserDownloadURL
        else {
            throw FeedError.feedNotFound
        }
        return feedURL
    }
}
