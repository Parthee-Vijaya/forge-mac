import SwiftUI
import StormbreakerKit

struct LogConsoleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.serverLog) { line in
                        Text(line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(line.stream == .stderr ? Color(red: 0.8, green: 0.2, blue: 0.2) : Theme.inkSoft)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(model.jsErrors.enumerated()), id: \.offset) { _, issue in
                        Text("⚠︎ \(issue.displayMessage)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 0.85, green: 0.45, blue: 0.0))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("logBottom")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.serverLog.count) {
                proxy.scrollTo("logBottom", anchor: .bottom)
            }
        }
        .background(Theme.fill)
    }
}
