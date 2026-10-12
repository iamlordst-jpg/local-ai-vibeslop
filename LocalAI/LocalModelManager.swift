import Foundation
import llama

enum LocalModelError: LocalizedError {
    case loadFailed
    case contextFailed
    case promptTooLong

    var errorDescription: String? {
        switch self {
        case .loadFailed: return "The GGUF model could not be loaded. Check that the file is valid and supported."
        case .contextFailed: return "llama.cpp could not create an inference context."
        case .promptTooLong: return "The conversation is too long for the current context. Start a new chat or shorten the system prompt."
        }
    }
}

private func addToken(_ batch: inout llama_batch, _ token: llama_token, _ position: llama_pos, _ logits: Bool) {
    let index = Int(batch.n_tokens)
    batch.token[index] = token
    batch.pos[index] = position
    batch.n_seq_id[index] = 1
    batch.seq_id[index]![0] = 0
    batch.logits[index] = logits ? 1 : 0
    batch.n_tokens += 1
}

actor LlamaContext {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocabulary: OpaquePointer
    private var batch: llama_batch

    private init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.vocabulary = llama_model_get_vocab(model)
        self.batch = llama_batch_init(2048, 0, 1)
    }

    deinit {
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    static func create(path: String) throws -> LlamaContext {
        llama_backend_init()
        var parameters = llama_model_default_params()
#if targetEnvironment(simulator)
        parameters.n_gpu_layers = 0
#endif
        guard let model = llama_model_load_from_file(path, parameters) else {
            llama_backend_free()
            throw LocalModelError.loadFailed
        }

        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = 2048
        let threads = max(2, min(6, ProcessInfo.processInfo.processorCount - 2))
        contextParameters.n_threads = Int32(threads)
        contextParameters.n_threads_batch = Int32(threads)

        guard let context = llama_init_from_model(model, contextParameters) else {
            llama_model_free(model)
            llama_backend_free()
            throw LocalModelError.contextFailed
        }
        return LlamaContext(model: model, context: context)
    }

    func generate(prompt: String, temperature: Float, maxTokens: Int) throws -> String {
        let tokenIDs = tokenize(prompt)
        guard !tokenIDs.isEmpty, tokenIDs.count < 1900 else {
            throw LocalModelError.promptTooLong
        }

        llama_memory_clear(llama_get_memory(context), true)
        batch.n_tokens = 0
        for (index, token) in tokenIDs.enumerated() {
            addToken(&batch, token, Int32(index), false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1
        guard llama_decode(context, batch) == 0 else {
            throw LocalModelError.contextFailed
        }

        let samplerParameters = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParameters) else {
            throw LocalModelError.contextFailed
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(max(0.01, temperature)))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))

        let limit = max(1, min(maxTokens, 4096))
        var position = Int32(tokenIDs.count)
        var output = [CChar]()
        var answer = ""

        for _ in 0..<limit {
            let token = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
            if llama_vocab_is_eog(vocabulary, token) { break }

            output.append(contentsOf: tokenPiece(token))
            if let decoded = String(validatingUTF8: output + [0]) {
                answer += decoded
                output.removeAll(keepingCapacity: true)
            } else if let validSuffix = validUTF8Suffix(output) {
                answer += validSuffix.text
                output = validSuffix.remaining
            }

            batch.n_tokens = 0
            addToken(&batch, token, position, true)
            guard llama_decode(context, batch) == 0 else { break }
            position += 1
        }

        if !output.isEmpty { answer += String(decoding: output.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        return answer.replacingOccurrences(of: "<|im_end|>", with: "").replacingOccurrences(of: "<|im_start|>", with: "").replacingOccurrences(of: "<|endoftext|>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(_ text: String) -> [llama_token] {
        let capacity = text.utf8.count + 2
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { tokens.deallocate() }
        let count = llama_tokenize(vocabulary, text, Int32(text.utf8.count), tokens, Int32(capacity), true, false)
        guard count > 0 else { return [] }
        return (0..<Int(count)).map { tokens[$0] }
    }

    private func tokenPiece(_ token: llama_token) -> [CChar] {
        let capacity = 256
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let count = llama_token_to_piece(vocabulary, token, buffer, Int32(capacity), 0, false)
        if count < 0 {
            let needed = Int(-count)
            let larger = UnsafeMutablePointer<Int8>.allocate(capacity: needed)
            defer { larger.deallocate() }
            let actual = llama_token_to_piece(vocabulary, token, larger, Int32(needed), 0, false)
            return (0..<max(0, Int(actual))).map { larger[$0] }
        }
        return (0..<max(0, Int(count))).map { buffer[$0] }
    }

    private func validUTF8Suffix(_ bytes: [CChar]) -> (text: String, remaining: [CChar])? {
        guard !bytes.isEmpty else { return nil }
        for split in stride(from: bytes.count - 1, through: 0, by: -1) {
            let prefix = Array(bytes[0...split])
            if let text = String(validatingUTF8: prefix + [0]) {
                return (text, Array(bytes.dropFirst(split + 1)))
            }
        }
        return nil
    }
}

@MainActor
final class LocalModelManager: ObservableObject {
    @Published private(set) var status = "Model not downloaded"
    @Published private(set) var isBusy = false
    @Published private(set) var isLoaded = false
    @Published var selectedModelID = "qwen05" {
        didSet {
            guard selectedModelID != oldValue else { return }
            context = nil
            isLoaded = false
            status = "Selected \\(selectedModel.title) • load this model to chat"
        }
    }

    struct ModelOption: Identifiable, Hashable {
        let id: String
        let title: String
        let filename: String
        let url: String
        let size: String
        let note: String
    }

    let availableModels: [ModelOption] = [
        .init(id: "qwen05", title: "Qwen2.5 0.5B Instruct (fastest)", filename: "Qwen2.5-0.5B-Instruct-Q4_K_M.gguf", url: "https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf?download=true", size: "~400 MB", note: "Best chance of running on iPhone 11; weakest answers."),
        .init(id: "qwen15", title: "Qwen2.5 1.5B Instruct (better)", filename: "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf", url: "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf?download=true", size: "~1 GB", note: "Better quality; may be slower and memory-heavy."),
        .init(id: "qwen3", title: "Qwen2.5 3B Instruct (stronger)", filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf", url: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf?download=true", size: "~2 GB", note: "Most capable option here; may fail to load or cause iOS to close the app.")
    ]
    var selectedModel: ModelOption { availableModels.first(where: { $0.id == selectedModelID }) ?? availableModels[0] }
    private var context: LlamaContext?

    private var modelFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(selectedModel.filename)
    }

    func downloadAndLoad() async {
        guard !isBusy else { return }
        isBusy = true
        isLoaded = false
        defer { isBusy = false }

        do {
            if !FileManager.default.fileExists(atPath: modelFileURL.path) {
                status = "Downloading model (\(selectedModel.size))… keep the app open"
                guard let url = URL(string: selectedModel.url) else { throw URLError(.badURL) }
                let (temporaryURL, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                try? FileManager.default.removeItem(at: modelFileURL)
                try FileManager.default.moveItem(at: temporaryURL, to: modelFileURL)
            }

            status = "Loading model into memory…"
            let path = modelFileURL.path
            let newContext = try await Task.detached(priority: .userInitiated) {
                try LlamaContext.create(path: path)
            }.value
            context = newContext
            isLoaded = true
            status = "Model ready • runs offline"
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    func generate(prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        guard let context else { throw LocalModelError.loadFailed }
        return try await context.generate(prompt: prompt, temperature: Float(temperature), maxTokens: maxTokens)
    }
}
