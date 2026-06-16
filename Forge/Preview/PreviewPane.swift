import SwiftUI
import ForgeKit

struct PreviewPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            PreviewToolbar()
            Divider().overlay(Theme.border)
            ZStack {
                Theme.fill
                // Keep the WebView mounted (opacity) so HMR + state survive a
                // switch to Code and back.
                previewLayer
                    .opacity(model.rightPaneMode == .preview ? 1 : 0)
                    .allowsHitTesting(model.rightPaneMode == .preview)
                if model.rightPaneMode == .code {
                    CodePane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.canvas)
    }

    @ViewBuilder private var previewLayer: some View {
        ZStack {
            // A19: keep the WebView mounted even with no URL yet, so a project
            // switch / dev-server restart reuses the same (warm) instance and just
            // loads a new URL — instead of remounting. BuildingView overlays it
            // until a URL is ready.
            DeviceChrome(width: model.previewWidth) {   // C6: device bezels in tablet/phone mode
                WebView(url: model.previewURL, reloadToken: model.reloadToken, selectMode: model.selectMode,
                        onRuntimeIssue: { model.handleRuntimeIssue($0) },
                        onElementSelected: { model.handleElementSelected(tag: $0, text: $1, className: $2, selector: $3) })
                    .frame(maxWidth: model.previewWidth.maxWidth ?? .infinity, maxHeight: .infinity)
            }
            .opacity(model.previewURL == nil ? 0 : 1)
            .animation(.smooth(duration: 0.3), value: model.previewWidth)
            if model.previewURL == nil {
                BuildingView(statusText: model.displayStatus,
                             lastLog: model.serverLog.last?.text,
                             isBusy: model.isBusy || model.isStartingPreview,
                             phase: model.phase,
                             serverPhase: model.serverPhase,
                             onRestart: model.previewServerDown ? { model.restartDevServer() } : nil)
            }
        }
        // C13: a friendly native error card over the preview (instead of only the
        // raw Vite/console overlay) with a one-tap repair.
        .overlay(alignment: .bottom) {
            if model.hasFixableErrors, let first = model.jsErrors.first {
                PreviewErrorCard(issue: first,
                                 extraCount: model.jsErrors.count - 1,
                                 onFix: { model.fixErrors() },
                                 onDismiss: { withAnimation { model.dismissRuntimeErrors() } })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: model.hasFixableErrors)
    }
}

/// C13: a native runtime-error card shown over the preview, with a "Fix det" button
/// that hands the error to the self-correction loop.
private struct PreviewErrorCard: View {
    let issue: RuntimeIssue
    let extraCount: Int
    var onFix: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning).font(.system(size: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(extraCount > 0 ? "Runtime-fejl · \(extraCount + 1) i alt" : "Runtime-fejl")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(issue.displayMessage)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(3).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 6) {
                Button(action: onFix) {
                    Text("Fix det").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                Button(action: onDismiss) {
                    Text("Skjul").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: 520)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.warning.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .padding(20)
    }
}

private struct PreviewToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                modeButton("Preview", .preview)
                modeButton("Code", .code)
            }
            .padding(2).background(Theme.fill, in: RoundedRectangle(cornerRadius: 9))

            if model.rightPaneMode == .preview {
                deviceToggles
                urlPill
                Button { model.toggleSelectMode() } label: {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 12))
                        .foregroundStyle(model.selectMode ? Theme.onAccent : Theme.inkSoft)
                        .frame(width: 30, height: 28)
                        .background(model.selectMode ? Theme.accent : Theme.fill,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusS))
                }
                .buttonStyle(.plain).disabled(model.previewURL == nil)
                .help("Select an element to edit")
                .accessibilityLabel("Vælg element at redigere")
                Button { model.reloadPreview() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(IconButtonStyle()).disabled(model.previewURL == nil)
                    .help("Genindlæs preview").accessibilityLabel("Genindlæs preview")
                Button { model.openInBrowser() } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(IconButtonStyle()).disabled(model.previewURL == nil)
                    .help("Åbn i browser").accessibilityLabel("Åbn preview i browser")
                Button { model.shareLiveLink() } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(IconButtonStyle()).disabled(model.previewURL == nil)
                    .help("Del live-link (LAN/Tailscale)").accessibilityLabel("Del live-link")
                Menu {
                    ForEach(StylePresets.all) { preset in
                        Button(preset.name) { model.applyStyle(preset) }
                    }
                } label: {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .frame(width: 30, height: 28)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.radiusS))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30)
                .disabled(model.previewURL == nil || model.isBusy)
                .help("Skift stil").accessibilityLabel("Skift visuel stil")
                Button { model.showDeploy = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowtriangle.up.circle.fill").font(.system(size: 11))
                        Text("Deploy").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.previewURL == nil)
                .popover(isPresented: $model.showDeploy, arrowEdge: .bottom) { DeployPanel() }
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.canvas)
    }

    private func modeButton(_ title: String, _ mode: AppModel.RightPaneMode) -> some View {
        Button {
            if mode == .code { model.enterCodeMode() } else { model.rightPaneMode = .preview }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.rightPaneMode == mode ? Theme.ink : Theme.inkFaint)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(model.rightPaneMode == mode ? Theme.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var deviceToggles: some View {
        HStack(spacing: 2) {
            ForEach(AppModel.PreviewWidth.allCases, id: \.self) { width in
                Button { model.previewWidth = width } label: {
                    Image(systemName: width.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(model.previewWidth == width ? Theme.ink : Theme.inkFaint)
                        .frame(width: 26, height: 22)
                        .background(model.previewWidth == width ? Theme.surface : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(width.accessibilityName)
                .accessibilityAddTraits(model.previewWidth == width ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 9))
    }

    private var urlPill: some View {
        HStack(spacing: 6) {
            Circle().fill(model.previewURL != nil ? Theme.positive : Theme.inkFaint)
                .frame(width: 6, height: 6)
            Text(model.previewURL?.absoluteString ?? "starting dev server…")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let px = model.previewWidth.pixelLabel {
                Text(px)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Theme.fill, in: Capsule())
    }
}

/// C6: wraps the preview in a device bezel for tablet/phone widths; passes content
/// through untouched at full width.
private struct DeviceChrome<Content: View>: View {
    let width: AppModel.PreviewWidth
    @ViewBuilder var content: Content

    var body: some View {
        if width == .full {
            content
        } else {
            let outer: CGFloat = width == .phone ? 36 : 22
            content
                .clipShape(RoundedRectangle(cornerRadius: outer - 9))
                .padding(width == .phone ? 9 : 11)
                .background(RoundedRectangle(cornerRadius: outer).fill(Color(white: 0.13)))
                .overlay(alignment: .top) {
                    Capsule().fill(Color.black.opacity(0.55))   // camera / notch hint
                        .frame(width: width == .phone ? 52 : 68, height: 5)
                        .padding(.top, width == .phone ? 4 : 5)
                }
                .overlay(RoundedRectangle(cornerRadius: outer).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 22, y: 8)
                .padding(24)
        }
    }
}

private struct BuildingView: View {
    let statusText: String
    let lastLog: String?
    var isBusy: Bool = true
    var phase: AgentState = .idle
    var serverPhase: DevServerPhase = .idle
    var onRestart: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Text("Forge")
                .font(Theme.wordmark(28))
                .foregroundStyle(Theme.ink.opacity(0.9))
            if isBusy {   // C8: step timeline (the active step carries its own spinner)
                BuildTimeline(phase: phase, serverPhase: serverPhase, hasPreview: false)
            }
            HStack(spacing: 8) {
                Text(statusText).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            }
            if let lastLog, !lastLog.isEmpty {
                Text(lastLog)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 380)
            }
            if let onRestart {
                Button(action: onRestart) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                        Text("Genstart preview").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(28)
    }
}
