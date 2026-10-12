import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let text: String
    enum Role { case user, assistant }
}

struct ChatView: View {
    @AppStorage("systemPrompt") private var systemPrompt = "You are ST Local AI. Match the user's requested tone and style. Be direct, creative, and useful."
    @AppStorage("temperature") private var temperature = 0.7
    @AppStorage("maxTokens") private var maxTokens = 256
    @StateObject private var model = LocalModelManager()
    @State private var messages: [ChatMessage] = [ChatMessage(role: .assistant, text: "Welcome to ST Local AI. Download the local model in Settings to start chatting. The first download is about 400 MB; after that, you can use it offline.")]
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var isGenerating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "cpu").font(.title2).foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ST Local AI").font(.headline)
                        Text(model.isLoaded ? "LOCAL MODEL READY" : "ON-DEVICE AI").font(.caption2).foregroundStyle(.secondary)
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
                if isGenerating {
                    HStack { ProgressView().tint(.purple); Text("Thinking on this iPhone…").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message ST Local AI…", text: $draft, axis: .vertical).lineLimit(1...5).padding(12).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44).background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? .gray : .purple, in: Circle())
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating).accessibilityLabel("Send message")
                }.padding()
            }
            .background(Color(red: 0.055, green: 0.05, blue: 0.08))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) { SettingsView(systemPrompt: $systemPrompt, temperature: $temperature, maxTokens: $maxTokens, model: model) }
        }
    }

    private func sendMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        guard model.isLoaded else {
            messages.append(ChatMessage(role: .assistant, text: "The model isn't loaded yet. Open Settings and tap Download & Load Model first."))
            draft = ""
            return
        }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        isGenerating = true

        let history = messages.suffix(10).map { message in
            switch message.role {
            case .user: return "<|im_start|>user\n\(message.text)<|im_end|>\n"
            case .assistant: return "<|im_start|>assistant\n\(message.text)<|im_end|>\n"
            }
        }.joined()
        let prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n\(history)<|im_start|>assistant\n"

        Task {
            do {
                let response = try await model.generate(prompt: prompt, temperature: temperature, maxTokens: maxTokens)
                messages.append(ChatMessage(role: .assistant, text: response.isEmpty ? "(The model returned an empty response. Try again.)" : response))
            } catch {
                messages.append(ChatMessage(role: .assistant, text: "Generation error: \(error.localizedDescription)"))
            }
            isGenerating = false
        }
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
    @ObservedObject var model: LocalModelManager
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
                    Stepper("Maximum output: \(maxTokens) tokens", value: $maxTokens, in: 64...1024, step: 64)
                }
                Section("Local model") {
                    Label(model.status, systemImage: model.isLoaded ? "checkmark.circle.fill" : "cpu")
                    Button {
                        Task { await model.downloadAndLoad() }
                    } label: {
                        if model.isBusy {
                            HStack { ProgressView(); Text("Working…") }
                        } else {
                            Text(model.isLoaded ? "Reload Model" : "Download & Load Model")
                        }
                    }.disabled(model.isBusy || model.isLoaded)
                    Text("Qwen 2.5 0.5B Instruct • Q4_K_M • roughly 400 MB. The first download needs internet. Inference runs on-device afterward. Keep the app open while downloading/loading.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Label("No API key or cloud inference", systemImage: "lock.shield")
                    Text("Your prompts are sent to the model running inside this app. The model download comes from Hugging Face; chat messages are not sent to an AI server.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
