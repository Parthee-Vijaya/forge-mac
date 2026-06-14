import SwiftUI
import ForgeKit

/// The prompt input — used both on the empty-state hero and in the chat panel.
/// Enter sends, Shift+Enter inserts a newline. Text is explicitly inked so it's
/// always visible.
struct Composer: View {
    @Binding var text: String
    var placeholder: String
    var isBusy: Bool
    var autofocus: Bool = false
    var onSubmit: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .lineLimit(1...8)
                .focused($focused)
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    if canSend { onSubmit() }
                    return .handled
                }

            Button(action: onSubmit) {
                Group {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(Theme.onAccent)
                    } else {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                .frame(width: 30, height: 30)
                .background(canSend || isBusy ? Theme.accent : Theme.borderStrong, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusL))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusL)
                .strokeBorder(focused ? Theme.borderStrong : Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
        .onAppear { if autofocus { focused = true } }
    }
}

/// Compact model selector (green dot = local, blue = cloud).
struct ModelPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Menu {
            ForEach(model.availableModels) { config in
                Button {
                    model.selectedModelID = config.id
                } label: {
                    if config.id == model.selectedModelID {
                        Label(config.displayName, systemImage: "checkmark")
                    } else {
                        Text(config.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.selectedModel.kind == .ollamaNative ? Theme.positive : Color.blue)
                    .frame(width: 6, height: 6)
                Text(model.selectedModel.displayName)
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.fill, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Small monospace file pill shown under an assistant message.
struct FileChip: View {
    let path: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text").font(.system(size: 10))
            Text(path).font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}
