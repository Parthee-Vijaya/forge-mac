import Foundation

/// Fetches readable text for a URL the user pasted into a prompt, so the agent
/// answers from REAL content instead of hallucinating (a local model otherwise just
/// guesses from the URL's words). GitHub repo URLs resolve to the README + repo
/// metadata; other URLs return the page text with HTML stripped. Network failures
/// return nil — the caller then tells the model to admit it couldn't read it.
public enum WebContent {

    /// Extract http(s) URLs from free text (trailing punctuation trimmed).
    public static func extractURLs(_ text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"https?://[^\s)<>"'`]+"#) else { return [] }
        let ns = text as NSString
        var seen = Set<String>(); var out: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var u = ns.substring(with: m.range)
            while let last = u.last, ".,;:!?)]}".contains(last) { u.removeLast() }
            if !u.isEmpty, seen.insert(u).inserted { out.append(u) }
        }
        return out
    }

    /// owner/repo from a github.com URL, or nil (ignores gist/raw/non-repo paths).
    public static func githubRepo(_ urlString: String) -> (owner: String, repo: String)? {
        guard let url = URL(string: urlString), (url.host ?? "").hasSuffix("github.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        return (parts[0], repo)
    }

    /// Fetch readable content for `urlString`, capped at `maxChars`. nil on failure.
    public static func fetch(_ urlString: String, maxChars: Int = 8000) async -> String? {
        if let gh = githubRepo(urlString) { return await fetchGitHub(gh.owner, gh.repo, maxChars: maxChars) }
        return await fetchPage(urlString, maxChars: maxChars)
    }

    /// Run a web search with NO API key and return the top results as
    /// "N. title / url / snippet" text the model can read. Primary source is
    /// DuckDuckGo's lite HTML endpoint (scraped); on failure it falls back to DDG's
    /// official JSON instant-answer API. nil only when both come up empty.
    public static func search(_ query: String, maxResults: Int = 5, maxChars: Int = 6000) async -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        if let data = await get("https://lite.duckduckgo.com/lite/?q=\(q)",
                                userAgent: browserUA, referer: "https://lite.duckduckgo.com/"),
           let html = String(data: data, encoding: .utf8) {
            let results = parseSearchResults(html, max: maxResults)
            if !results.isEmpty {
                let body = results.enumerated().map { i, r in
                    "\(i + 1). \(r.title)\n   \(r.url)\(r.snippet.isEmpty ? "" : "\n   \(r.snippet)")"
                }.joined(separator: "\n\n")
                return String(body.prefix(maxChars))
            }
        }
        // Fallback: official instant-answer JSON (reliable for well-known topics).
        return await instantAnswer(q, maxChars: maxChars)
    }

    private static func instantAnswer(_ encodedQuery: String, maxChars: Int) async -> String? {
        guard let data = await get(
                "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json&no_html=1&t=stormbreaker"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out = ""
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
            out += abstract
            if let url = json["AbstractURL"] as? String, !url.isEmpty { out += "\n\nKilde: \(url)" }
        }
        if let related = json["RelatedTopics"] as? [[String: Any]] {
            let topics = related.compactMap { $0["Text"] as? String }.prefix(5)
            if !topics.isEmpty { out += "\n\nRelateret:\n" + topics.map { "- \($0)" }.joined(separator: "\n") }
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxChars))
    }

    // MARK: - Internals

    static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0 Safari/537.36"

    private static func get(_ urlString: String, accept: String? = nil,
                            userAgent: String = "Stormbreaker", referer: String? = nil) async -> Data? {
        // SSRF guard: refuse internal/loopback/link-local/private/CGNAT targets so a
        // crafted URL — or a prompt-injected web-fetch — can't reach the cloud
        // metadata endpoint, localhost services, or the LAN/Tailscale range.
        guard let url = URL(string: urlString), !isBlockedURL(urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")   // GitHub API requires a UA; sites prefer a browser UA
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }   // DDG lite needs one
        do {
            // The delegate re-checks every redirect hop, so a public URL can't 302
            // into an internal address.
            let (data, resp) = try await URLSession.shared.data(for: req, delegate: SSRFRedirectGuard())
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch { return nil }
    }

    // MARK: - SSRF protection

    /// True if `urlString` is not http(s) with a public host. Internal names
    /// (`localhost`, `*.local`, `*.internal`), IP literals in private/loopback/
    /// link-local/CGNAT ranges, and hostnames that RESOLVE to such an address (DNS
    /// rebinding) are all blocked.
    static func isBlockedURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = url.host, !rawHost.isEmpty else { return true }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || host.hasSuffix(".internal") || host == "ip6-localhost" || host == "ip6-loopback" { return true }
        if let v4 = parseIPv4(host) { return isBlockedIPv4(v4) }
        if let v6 = parseIPv6(host) { return isBlockedIPv6(v6) }
        // Hostname: block if ANY resolved address is internal.
        for ip in resolveHost(host) {
            if let v4 = parseIPv4(ip), isBlockedIPv4(v4) { return true }
            if let v6 = parseIPv6(ip), isBlockedIPv6(v6) { return true }
        }
        return false
    }

    static func parseIPv4(_ s: String) -> UInt32? {
        var addr = in_addr()
        guard s.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)   // host byte order
    }

    static func parseIPv6(_ s: String) -> [UInt8]? {
        var addr = in6_addr()
        guard s.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }   // 16 bytes, network order
    }

    static func isBlockedIPv4(_ a: UInt32) -> Bool {
        func inRange(_ base: UInt32, _ prefix: Int) -> Bool {
            let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
            return (a & mask) == (base & mask)
        }
        return inRange(0x0000_0000, 8)    // 0.0.0.0/8     this-network / unspecified
            || inRange(0x0A00_0000, 8)    // 10/8          private
            || inRange(0x6440_0000, 10)   // 100.64/10     CGNAT (Tailscale)
            || inRange(0x7F00_0000, 8)    // 127/8         loopback
            || inRange(0xA9FE_0000, 16)   // 169.254/16    link-local (incl. metadata)
            || inRange(0xAC10_0000, 12)   // 172.16/12     private
            || inRange(0xC0A8_0000, 16)   // 192.168/16    private
            || inRange(0xC612_0000, 15)   // 198.18/15     benchmarking
            || inRange(0xE000_0000, 4)    // 224/4         multicast
            || inRange(0xF000_0000, 4)    // 240/4         reserved
    }

    static func isBlockedIPv6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return true }
        if b.allSatisfy({ $0 == 0 }) { return true }                       // ::      unspecified
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true } // ::1     loopback
        if (b[0] & 0xFE) == 0xFC { return true }                          // fc00::/7 unique-local
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }          // fe80::/10 link-local
        if b[0] == 0xFF { return true }                                   // ff00::/8 multicast
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {  // ::ffff:0:0/96 v4-mapped
            let v4 = (UInt32(b[12]) << 24) | (UInt32(b[13]) << 16) | (UInt32(b[14]) << 8) | UInt32(b[15])
            return isBlockedIPv4(v4)
        }
        return false
    }

    private static func resolveHost(_ host: String) -> [String] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return [] }
        defer { freeaddrinfo(first) }
        var out: [String] = []
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let cur = p {
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(cur.pointee.ai_addr, cur.pointee.ai_addrlen,
                           &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                out.append(String(decoding: bytes, as: UTF8.self))
            }
            p = cur.pointee.ai_next
        }
        return out
    }

    private static func fetchGitHub(_ owner: String, _ repo: String, maxChars: Int) async -> String? {
        var out = ""
        if let data = await get("https://api.github.com/repos/\(owner)/\(repo)"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            out += "REPO: \(owner)/\(repo)\n"
            if let d = json["description"] as? String, !d.isEmpty { out += "Beskrivelse: \(d)\n" }
            if let l = json["language"] as? String, !l.isEmpty { out += "Hovedsprog: \(l)\n" }
            if let s = json["stargazers_count"] as? Int { out += "Stjerner: \(s)\n" }
            if let t = json["topics"] as? [String], !t.isEmpty { out += "Emner: \(t.joined(separator: ", "))\n" }
            out += "\n"
        }
        // The /readme endpoint resolves any branch/filename (README.md, .rst, …).
        if let data = await get("https://api.github.com/repos/\(owner)/\(repo)/readme",
                                accept: "application/vnd.github.raw"),
           let readme = String(data: data, encoding: .utf8) {
            out += "README:\n" + readme
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxChars))
    }

    private static func fetchPage(_ urlString: String, maxChars: Int) async -> String? {
        guard let data = await get(urlString, userAgent: browserUA),
              let html = String(data: data, encoding: .utf8) else { return nil }
        let text = stripHTML(html)
        return text.isEmpty ? nil : String(text.prefix(maxChars))
    }

    /// Parse DuckDuckGo lite's HTML results into ordered (title, url, snippet) rows.
    /// Walks `result-link` anchors and `result-snippet` cells in DOCUMENT ORDER and
    /// pairs each link with the snippet that follows it, so interleaved ads / "more
    /// info" links don't misalign snippets. Defensive: returns whatever it can, []
    /// if the markup shape changed.
    static func parseSearchResults(_ html: String, max: Int) -> [(title: String, url: String, snippet: String)] {
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)
        enum Tok { case link(title: String, url: String); case snippet(String) }
        var toks: [(loc: Int, tok: Tok)] = []

        if let re = try? NSRegularExpression(pattern: #"<a\b([^>]*)>([\s\S]*?)</a>"#, options: [.caseInsensitive]) {
            for m in re.matches(in: html, range: full) {
                let attrs = ns.substring(with: m.range(at: 1))
                guard attrs.range(of: "result-link", options: .caseInsensitive) != nil else { continue }
                let title = stripHTML(ns.substring(with: m.range(at: 2)))
                guard !title.isEmpty, title.lowercased() != "more info" else { continue }
                guard let href = firstGroup(attrs, #"href=['\"]([^'\"]+)['\"]"#) else { continue }
                let url = decodeDDGRedirect(href)
                guard !isAdURL(url) else { continue }
                toks.append((m.range.location, .link(title: title, url: url)))
            }
        }
        if let re = try? NSRegularExpression(
            pattern: #"<td\b[^>]*class=['\"][^'\"]*result-snippet[^'\"]*['\"][^>]*>([\s\S]*?)</td>"#,
            options: [.caseInsensitive]) {
            for m in re.matches(in: html, range: full) {
                let snip = stripHTML(ns.substring(with: m.range(at: 1)))
                if !snip.isEmpty { toks.append((m.range.location, .snippet(snip))) }
            }
        }
        toks.sort { $0.loc < $1.loc }

        var out: [(String, String, String)] = []
        var pending: (title: String, url: String)?
        for (_, tok) in toks {
            switch tok {
            case .link(let title, let url):
                if let p = pending { out.append((p.title, p.url, "")) }   // prior link had no snippet
                pending = (title, url)
            case .snippet(let s):
                if let p = pending { out.append((p.title, p.url, s)); pending = nil }
            }
            if out.count >= max { pending = nil; break }
        }
        if let p = pending, out.count < max { out.append((p.title, p.url, "")) }
        return out
    }

    /// DDG wraps result links as `//duckduckgo.com/l/?uddg=<percent-encoded-url>`
    /// (with `&amp;`-encoded separators in the lite markup). Decode back to the real URL.
    static func decodeDDGRedirect(_ href: String) -> String {
        let h = href.replacingOccurrences(of: "&amp;", with: "&")
        guard let r = h.range(of: "uddg=") else {
            return h.hasPrefix("//") ? "https:" + h : h
        }
        var enc = String(h[r.upperBound...])
        if let amp = enc.firstIndex(of: "&") { enc = String(enc[..<amp]) }
        return enc.removingPercentEncoding ?? h
    }

    /// Ad / tracker redirects DDG mixes into results (after decoding) — skip them.
    private static func isAdURL(_ url: String) -> Bool {
        ["/y.js", "ad_domain", "ad_provider", "bing.com/aclick", "duckduckgo.com/l/"]
            .contains { url.contains($0) }
    }

    /// First capture group of the first match of `pattern` in `text`, or nil.
    private static func firstGroup(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Basic HTML → text: drop script/style/nav/footer, strip tags, decode common
    /// entities, collapse whitespace. Good enough to feed a model real page text.
    static func stripHTML(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "head", "noscript", "svg"] {
            s = s.replacingOccurrences(of: "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>", with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n[ \\t]*(\\n[ \\t]*)+", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Re-applies the SSRF host check to every redirect target, so a public URL can't
/// 302 into an internal address. Stateless → safe to share.
private final class SSRFRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let u = request.url?.absoluteString, WebContent.isBlockedURL(u) {
            completionHandler(nil)        // refuse the redirect
        } else {
            completionHandler(request)
        }
    }
}
