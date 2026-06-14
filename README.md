# Forge

Local-first, open-source app builder for macOS — a native SwiftUI take on the
Lovable.dev / Bolt.new pattern. Type a prompt; an AI agent writes a
React + Vite + TypeScript + Tailwind project to disk; Forge runs it and shows a
live preview (WKWebView → local Vite dev server) with hot-module-reload.

## Layout

- `ForgeKit/` — the engine (Swift Package, pure Foundation): model router,
  streaming artifact parser, action executor, process/dev-server manager,
  agent loop. Builds and tests headlessly: `cd ForgeKit && swift test`.
- `Forge/` — the SwiftUI macOS app: chat pane + WKWebView preview. Generated
  into `Forge.xcodeproj` via `xcodegen generate`.

## Models

- Local default: **Ollama** `qwen2.5-coder:14b` via the native `/api/chat`
  endpoint (so `num_ctx` is set to 32768 — the OpenAI-compatible `/v1` path
  cannot set context and silently truncates input).
- Cloud: **NVIDIA NIM** / OpenAI (OpenAI-compatible SSE) + an **Anthropic** shim.
  Provide a key via the `FORGE_CLOUD_API_KEY` environment variable.

## Build

```sh
cd ForgeKit && swift build                         # engine (Command Line Tools is fine)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # tests need the Xcode toolchain
xcodegen generate                                  # generate the app project
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Forge.xcodeproj -scheme Forge build
```

See [HANDOFF.md](HANDOFF.md) for status, stack, gotchas, and the build plan.
