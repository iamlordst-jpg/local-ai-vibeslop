# ST Local AI

A free, offline-first iOS chat app built by ST. It uses [llama.cpp](https://github.com/ggml-org/llama.cpp) for on-device inference with GGUF models.

## Current implementation

- Native SwiftUI chat UI
- On-device llama.cpp runtime (compiled as an iOS XCFramework in GitHub Actions)
- Downloads **Qwen2.5-0.5B-Instruct Q4_K_M** (~400 MB) directly from Hugging Face on first use
- Runs generation locally after the model is downloaded; no API key or AI cloud service
- Editable system prompt, temperature, and output token limit

The initial model is intentionally small for the iPhone 11's memory limits. Larger models may be slower or fail to load. Model behavior depends on its training and license; the app exposes the system prompt and sampling controls but cannot guarantee every model will respond to every request.

## Build from an iPhone using GitHub Actions

1. Open the **Actions** tab in this repository.
2. Select **Build iOS app**, then **Run workflow** (or wait for a push-triggered run).
3. When the run succeeds, open it and download the `ST-Local-AI-unsigned-IPA` artifact.
4. The IPA is **unsigned**. Sign it with your existing sideloading workflow before installing it through LiveContainer.

The workflow compiles llama.cpp for iOS from its upstream source, then builds this app. The first build can take a while.

## First launch

1. Open **Settings** in ST Local AI.
2. Tap **Download & Load Model** and keep the app open while it downloads and loads the model.
3. After it says **Model ready • runs offline**, return to chat.

The model is stored in the app's Documents directory. Removing the app removes its local model file.

## Model and runtime licenses

- llama.cpp: MIT license, see upstream repository.
- Qwen2.5 model family: Apache-2.0; review the model card before redistributing model weights.
- This repository's app code: MIT.

## Project status

This is an early implementation. The GitHub Actions build must complete successfully before the IPA is considered build-verified. On-device speed and memory use still need to be tested on the iPhone 11.
