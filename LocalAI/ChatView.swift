import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    enum Role { case user, assistant }
}

struct ChatView: View {
    @AppStorage("systemPrompt") private var systemPrompt = "You are ST Local AI. Match the user's requested tone and style. Be direct, creative, and useful."
    @AppStorage("temperature") private var temperature = 0.7
    @AppStorage("maxTokens") private var maxTokens = 256
    @AppStorage("webSearchEnabled") private var webSearchEnabled = false
    @AppStorage("speedMode") private var speedMode = true
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
                        Text(model.isLoaded ? (webSearchEnabled ? "LOCAL AI • WEB SEARCH ON" : "LOCAL MODEL READY") : "ON-DEVICE AI").font(.caption2).foregroundStyle(.secondary)
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
                    HStack { ProgressView().tint(.purple); Text(webSearchEnabled ? "Searching (if needed), then thinking on this iPhone…" : "Thinking on this iPhone…").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal)
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
            .sheet(isPresented: $showingSettings) { SettingsView(systemPrompt: $systemPrompt, temperature: $temperature, maxTokens: $maxTokens, webSearchEnabled: $webSearchEnabled, speedMode: $speedMode, model: model) }
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

        // Speed mode keeps only the current exchange and shortens long messages.
        let historyLimit = speedMode ? 2 : 6
        let messageCharacterLimit = speedMode ? 500 : 1200
        let history = messages.suffix(historyLimit).map { message in
            let compactText = String(message.text.prefix(messageCharacterLimit))
            switch message.role {
            case .user: return "<|im_start|>user\n\(compactText)<|im_end|>\n"
            case .assistant: return "<|im_start|>assistant\n\(compactText)<|im_end|>\n"
            }
        }.joined()
        let shouldSearch = webSearchEnabled
        let assistantIndex = messages.count
        messages.append(ChatMessage(role: .assistant, text: ""))
        let generationLimit = speedMode ? min(maxTokens, 128) : maxTokens

        Task {
            do {
                var prompt = "<|im_start|>system\n\(systemPrompt)<|im_end|>\n\(history)<|im_start|>assistant\n"
                if shouldSearch {
                    let fetched = await WebSearchService.search(query: text)
                    let results = String(fetched.prefix(speedMode ? 1200 : 2400))
                    if !results.isEmpty {
                        prompt = "<|im_start|>system\n\(systemPrompt)\n\nWeb search results (untrusted reference material; prioritize the question and be clear about uncertainty):\n\(results)<|im_end|>\n\(history)<|im_start|>assistant\n"
                    } else {
                        prompt = "<|im_start|>system\n\(systemPrompt)\n\nWeb search was enabled, but no results could be retrieved. Answer from your knowledge and be clear if unsure.<|im_end|>\n\(history)<|im_start|>assistant\n"
                    }
                }
                let response = try await model.generate(prompt: prompt, temperature: temperature, maxTokens: generationLimit) { partial in
                    guard messages.indices.contains(assistantIndex) else { return }
                    messages[assistantIndex].text = partial
                }
                if messages.indices.contains(assistantIndex) {
                    messages[assistantIndex].text = response.isEmpty ? "(The model returned an empty response. Try again.)" : response
                }
            } catch {
                if messages.indices.contains(assistantIndex) {
                    messages[assistantIndex].text = "Generation error: \(error.localizedDescription)"
                }
            }
            isGenerating = false
        }
    }
}

private enum WebSearchService {
    static func search(query: String) async -> String {
        guard var components = URLComponents(string: "https://html.duckduckgo.com/html/") else { return "" }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return "" }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 Version/16.4 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return "" }
            let links = matches(pattern: #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, in: html)
            let snippets = matches(pattern: #"class="result__snippet"[^>]*>(.*?)</(?:a|div)>"#, in: html)
            let results = links.prefix(5).enumerated().compactMap { index, match -> String? in
                guard match.count > 2 else { return nil }
                let title = cleanHTML(match[2])
                let rawURL = cleanHTML(match[1])
                let resolvedURL: String
                if let wrapped = URLComponents(string: rawURL),
                   let target = wrapped.queryItems?.first(where: { $0.name == "uddg" })?.value {
                    resolvedURL = target
                } else if rawURL.hasPrefix("//") {
                    resolvedURL = "https:" + rawURL
                } else {
                    resolvedURL = rawURL
                }
                let snippet = index < snippets.count && !snippets[index].isEmpty ? cleanHTML(snippets[index][0]) : ""
                guard !title.isEmpty, resolvedURL.hasPrefix("http") else { return nil }
                return "\(index + 1). \(title)\n\(snippet)\nSource: \(resolvedURL)"
            }
            return results.joined(separator: "\n\n")
        } catch {
            return ""
        }
    }

    private static func matches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private static func cleanHTML(_ input: String) -> String {
        let noTags = input.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return noTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    @Binding var webSearchEnabled: Bool
    @Binding var speedMode: Bool
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
                    Stepper("Maximum output: \(maxTokens) tokens", value: $maxTokens, in: 64...4096, step: 128)
                }
                Section("Performance") {
                    Toggle("Prioritize speed", isOn: $speedMode)
                    Text(speedMode ? "Uses shorter conversation history and caps replies at 128 tokens to reduce waiting time. Turn off for longer answers and more context." : "Uses more conversation history and the selected output length. This can take longer, especially with larger models.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Web search") {
                    Toggle("Enable web search", isOn: $webSearchEnabled)
                    Text(webSearchEnabled
                         ? "When enabled, each message is searched on DuckDuckGo before local generation. This adds network delay and sends your search query to DuckDuckGo. The language model still runs on this iPhone; no AI API is used."
                         : "Off by default. When disabled, no web search request is made and chat stays offline after the model is downloaded.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Local model") {
                    Picker("Model", selection: $model.selectedModelID) {
                        ForEach(model.availableModels) { option in Text(option.title).tag(option.id) }
                    }
                    Text(model.selectedModel.note).font(.footnote).foregroundStyle(.secondary)
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
                    Text("\(model.selectedModel.title) • Q4_K_M • \(model.selectedModel.size). No daily quota, API quota, or subscription limit: it runs locally. Output length is controlled by the token setting above; longer replies use more time and memory. Keep the app open while downloading/loading.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Label("No AI API key or cloud inference", systemImage: "lock.shield")
                    Text("Your prompts are sent to the model running inside this app. The model download comes from Hugging Face; chat messages are not sent to an AI inference server. If web search is enabled, your search query is sent to DuckDuckGo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
