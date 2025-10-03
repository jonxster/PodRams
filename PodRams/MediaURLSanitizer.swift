import Foundation

struct MediaURLSanitizer {
    private static let httpsConvertibleHosts: Set<String> = [
        "dts.podtrac.com",
        "claritaspod.com",
        "pscrb.fm",
        "traffic.libsyn.com",
        "prfx.byspotify.com",
        "9to5mac.com",
        "feeds.9to5mac.com"
    ]

    static func sanitize(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http",
              let host = components.host?.lowercased() else {
            return url
        }

        if httpsConvertibleHosts.contains(host) || host.hasSuffix(".podtrac.com") {
            components.scheme = "https"
            if let upgraded = components.url {
                return upgraded
            }
        }

        return url
    }

    static func sanitize(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString) else { return nil }
        return sanitize(url)
    }
}
