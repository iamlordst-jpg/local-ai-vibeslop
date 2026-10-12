import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    enum Role { case user, assistant }
}

struct ChatView: View {
    @AppStorage("systemPrompt") private var systemPrompt = "You are ST Local AI, a helpful assistant. Follow the user's requested style and be clear about uncertainty."
    @AppStorage("temperature") private var temperature = 0.7
    @AppStorage("maxTokens") private var maxTokens = 512
    @State private var messages: [ChatMessage] = [ChatMessage(role: .assistant, text: "Welcome to ST Local AI. This is the first app shell. Local model inference is the next step.")]
    @State private var draft = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "cpu").font(.title2).foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ST Local AI").font(.headline)
                        Text("LOCAL MODEL • INTEGRATION PENDING").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.title3).padding(10).background(.white.opacity(0.08), in: Circle())
                    }.accessibilityLabel("Settings")
                }.padding()
                Divider().overlay(.white.opacity(0.1))
                ScrollView {
                    LazyVStack(spacing: 14) { ForEach(messages) { MessageBubble(message: $0) } }.padding()
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message ST Local AI…", text: $draft, axis: .vertical).lineLimit(1...5).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .purple, in: Circle())
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send message")
                }.padding()
            }
            .background(Color(red: 0.055, green: 0.05, blue: 0.08))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) { SettingsView(systemPrompt: $systemPrompt, temperature: $temperature, maxTokens: $maxTokens) }
        }
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        messages.append(ChatMessage(role: .assistant, text: "Local inference is not connected yet. The next milestone is integrating llama.cpp and a local model."))
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .assistant { bubble; Spacer(minLength: 36) }
            else { Spacer(minLength: 36); bubble }
        }
    }
    private var bubble: some View {
        Text(message.text).textSelection(.enabled).padding(13)
            .background(message.role == .user ? Color.purple.opacity(0.7) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct SettingsView: View {
    @Binding var systemPrompt: String
    @Binding var temperature: Double
    @Binding var maxTokens: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Behavior") {
                    Text("System prompt")
                    TextEditor(text: $systemPrompt).frame(minHeight: 150)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Temperature"); Spacer(); Text(temperature, format: .number.precision(.fractionLength(2))).monospacedDigit() }
                        Slider(value: $temperature, in: 0...1.5, step: 0.05)
                        Text("Higher values generally produce more varied output.").font(.caption).foregroundStyle(.secondary)
                    }
                    Stepper("Maximum output: \(maxTokens) tokens", value: $maxTokens, in: 64...2048, step: 64)
                }
                Section("Runtime") {
                    Label("No model loaded", systemImage: "exclamationmark.circle")
                    Text("Settings are saved locally. They will control generation after the local runtime is integrated.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
