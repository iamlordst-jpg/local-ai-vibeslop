# local-ai-vibeslop

**ST Local AI** — a free, on-device AI app project for iPhone.

The goal is to run open-weight language models locally, without paid APIs, subscriptions, or mandatory cloud inference. The app is being developed from an iPhone using GitHub and GitHub Actions.

## Current status

- [x] Initial SwiftUI app shell
- [x] Editable system prompt and generation settings UI
- [ ] Integrate a native local inference runtime
- [ ] Load a compatible GGUF model on device
- [ ] Verify fully offline generation on iPhone 11
- [ ] Model management, saved profiles, and local chat history

**Important:** the initial build is only the app shell. It does not generate AI responses until a local inference runtime and model are integrated. No API keys are needed.

## Build from GitHub on iPhone

1. Open the **Actions** tab.
2. Select **Build iOS app**.
3. Tap **Run workflow** on the `main` branch.
4. When it finishes, open the run and download the `unsigned-ipa` artifact.
5. Install/sign it using a compatible sideloading workflow. An unsigned IPA is not directly installable as-is.

The workflow uses a macOS GitHub-hosted runner and XcodeGen to generate the Xcode project.

## Model and runtime plan

The intended first runtime is [llama.cpp](https://github.com/ggml-org/llama.cpp), with a compatible quantized model. Model downloads and inference should happen on-device. The first model will be selected after verifying iOS compatibility, chat template, memory needs, and license.

## Free software and model licensing

This repository's original code is MIT-licensed. Third-party runtimes and downloaded models have their own licenses; check them before redistribution. The app will not bundle large model weights in this repository.

## Project structure

- `LocalAI/` — SwiftUI app
- `project.yml` — XcodeGen project definition
- `.github/workflows/build.yml` — automated iOS build
- `ThirdParty/README.md` — notes for runtime integration

Made by ST.
