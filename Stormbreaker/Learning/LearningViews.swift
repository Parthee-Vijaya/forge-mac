import SwiftUI

/// A contextual beginner explainer shown at a milestone (learning mode). Accent-
/// tinted card with a title, plain-Danish body, the English terms it teaches, and
/// a dismiss button. Appears once per lesson.
struct LessonCard: View {
    let lesson: Lesson
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: lesson.icon)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(lesson.title)
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Text("Lær").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            }

            Text(lesson.body)
                .font(.system(size: 12.5)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if !lesson.terms.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(lesson.terms) { TermRow(term: $0) }
                }
                .padding(.top, 2)
            }

            HStack {
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Text("Forstået").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radiusM))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

/// One term row: the English word + its short Danish explanation.
private struct TermRow: View {
    let term: Term
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(term.term)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
            Text(term.explanation)
                .font(.system(size: 11.5)).foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The always-available glossary — every term in plain Danish. Opened from the
/// book button in the chat header.
struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "book").font(.system(size: 13)).foregroundStyle(Theme.accent)
                Text("Ordbog").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Luk") { dismiss() }.buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ord du møder når du bygger — på engelsk (som de hedder i værktøjerne) med en dansk forklaring. Tryk på et ord for en dybere forklaring med eksempel.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                    ForEach(Lessons.glossary) { GlossaryRow(term: $0) }
                }
                .padding(16)
            }
        }
        .frame(width: 440, height: 560)
        .background(Theme.canvas)
        .preferredColorScheme(model.colorScheme)
    }
}

/// One glossary entry: short gloss always visible; tap to expand a richer
/// plain-language explanation + a concrete example (pre-written, always works),
/// with an "Uddyb med AI" button that goes deeper on demand via the model.
private struct GlossaryRow: View {
    @Environment(AppModel.self) private var model
    let term: Term
    @State private var expanded = false
    @State private var aiText: String?
    @State private var aiLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(term.term)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                        Text(term.explanation)
                            .font(.system(size: 12.5)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let d = Lessons.detail(for: term.term) {
                        Text(d.detail)
                            .font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 7) {
                            Text("Eksempel").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                            Text(d.example)
                                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let aiText {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("AI FORKLARER").font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Theme.inkFaint)
                            MarkdownView(text: aiText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.radiusS))
                    }

                    Button(action: deepen) {
                        HStack(spacing: 5) {
                            if aiLoading { ProgressView().controlSize(.small).scaleEffect(0.7) }
                            else { Image(systemName: "sparkles").font(.system(size: 10)) }
                            Text(aiLoading ? "Tænker…" : (aiText == nil ? "Uddyb med AI" : "Forklar igen"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(aiLoading)
                }
                .padding(.top, 8).padding(.bottom, 4).padding(.leading, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }

            Divider().overlay(Theme.border).opacity(0.4).padding(.top, 8)
        }
    }

    private func deepen() {
        aiLoading = true
        Task {
            let text = await model.explainTerm(term.term)
            aiText = text
            aiLoading = false
        }
    }
}
