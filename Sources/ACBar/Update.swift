import Foundation

/// A release on GitHub that is newer than the running app.
struct Update: Equatable {
    let version: String
    let url: URL

    private static let latestRelease = URL(string: "https://api.github.com/repos/Wedz0ff/thinq-ac-bar/releases/latest")!

    /// `release` is GitHub's "latest release" JSON. Nil unless it is newer than `current` and links to github.com.
    init?(release: [String: Any], current: String) {
        guard let tag = release["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard version.compare(current, options: .numeric) == .orderedDescending else { return nil }

        let assets = release["assets"] as? [[String: Any]] ?? []
        let diskImage = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".dmg") }
        guard let url = URL(string: diskImage ?? release["html_url"] as? String ?? ""),
              url.scheme == "https", url.host == "github.com" else { return nil }
        self.version = version
        self.url = url
    }

    /// Asks GitHub for the latest release. Any failure means "no update"; it is not worth an error message.
    static func check(current: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) async -> Update? {
        guard let current,
              let (data, _) = try? await URLSession.shared.data(from: latestRelease),
              let release = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Update(release: release, current: current)
    }
}
