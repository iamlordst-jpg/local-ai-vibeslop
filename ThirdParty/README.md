# Runtime and model

GitHub Actions builds the iOS XCFramework from the upstream [llama.cpp](https://github.com/ggml-org/llama.cpp) source. The generated framework is not committed to this repository.

The app downloads Qwen2.5-0.5B-Instruct Q4_K_M in-app from Hugging Face on first use. It is stored in the app's Documents directory and loaded by llama.cpp. Chat inference itself is local/offline after the download.

Model URL: https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF
