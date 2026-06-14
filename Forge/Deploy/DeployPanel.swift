import SwiftUI

/// Popover shown from the Deploy button: status, GitHub + Vercel links, log.
struct DeployPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if model.isDeploying {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.deployVercelURL != nil ? "checkmark.circle.fill" : "arrowtriangle.up.circle")
                        .foregroundStyle(model.deployVercelURL != nil ? Theme.positive : Theme.ink)
                }
                Text(headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }

            if let github = model.deployGithubURL {
                linkRow(label: "GitHub repo", url: github, icon: "chevron.left.forwardslash.chevron.right")
            }
            if let vercel = model.deployVercelURL {
                linkRow(label: "Live URL", url: vercel, icon: "globe")
            }

            if !model.deployLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.deployLog.suffix(80).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.inkFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 130)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
            }

            if !model.isDeploying {
                Button { model.deploy() } label: {
                    Text(model.deployVercelURL != nil ? "Redeploy" : "Deploy")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var headline: String {
        if model.isDeploying { return model.deployStatus.isEmpty ? "Deploying…" : model.deployStatus }
        if model.deployVercelURL != nil { return "Deployed 🎉" }
        return "Deploy to GitHub + Vercel"
    }

    private func linkRow(label: String, url: URL, icon: String) -> some View {
        Button { model.openURL(url) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    Text(url.absoluteString)
                        .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
            }
            .padding(10)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
