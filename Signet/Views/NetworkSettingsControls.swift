import SwiftUI

/// A section title with an ⓘ that shows the explanation on hover, instead of a paragraph
/// under the section.
struct SectionHeader: View {
    let title: String
    let help: String
    @State private var showing = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .onHover { showing = $0 }
                .popover(isPresented: $showing, arrowEdge: .bottom) {
                    Text(help).font(.callout).frame(width: 400, alignment: .leading).padding(12)
                }
                .help(help)
                .accessibilityLabel("About \(title)")
        }
    }
}

/// One text setting with its error line and Use Default / Apply buttons.
struct SettingField: View {
    let title: String
    let current: String
    let defaultValue: String
    let prompt: String
    var monospaced = false
    /// Applies the text; false when it was refused.
    let apply: (String) -> Bool
    let problem: (String) -> String
    let useDefault: () -> Void

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 8) {
                TextField("", text: $text, prompt: Text(prompt))
                    .font(monospaced ? .callout.monospaced() : .callout)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    .frame(minWidth: 300)
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                HStack {
                    Button("Use Default") { useDefault(); error = nil }
                        .disabled(current == defaultValue)
                    Button("Apply", action: submit)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines) == current)
                }
            }
        }
        .onAppear(perform: sync)
        .onChange(of: current) { sync() }
    }

    private func sync() {
        text = current
        error = nil
    }

    private func submit() {
        if apply(text) { error = nil } else { error = problem(text) }
    }
}
