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

    // MARK: - Internals

    private static func get(_ urlString: String, accept: String? = nil) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Stormbreaker", forHTTPHeaderField: "User-Agent")   // GitHub API requires a UA
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch { return nil }
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
        guard let data = await get(urlString), let html = String(data: data, encoding: .utf8) else { return nil }
        let text = stripHTML(html)
        return text.isEmpty ? nil : String(text.prefix(maxChars))
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
