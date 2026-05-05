<div align="center">
  <img src="OpenVoice/OpenVoice/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="160" height="160" alt="OpenVoice icon" />
  <h1>OpenVoice</h1>
  <p>System-wide voice dictation for macOS. Press a key, speak, press again — your transcribed text is pasted into whatever app is in front. 100% local, offline, free.</p>
  <p>
    <a href="README.ru.md">Русская версия</a>
  </p>
</div>

A free, MIT-licensed alternative to commercial dictation apps. Built around [whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal acceleration on Apple Silicon.

## Features

- 🎙️ **Local transcription** via whisper.cpp — your voice never leaves your machine
- ⚡ **Metal acceleration** on Apple Silicon
- 🔑 **Single-modifier hotkey** (right ⌘ by default) — press once to start, again to stop
- 📋 **Auto-paste** into the active text field via system pasteboard
- 🪟 **Liquid Glass HUD** at the bottom of the screen with a live waveform and timer
- 📚 **Transcription history** with search and copy
- 🔤 **Custom replacement dictionary** for terms Whisper mishears (e.g. `gpt-ee` → `GPT`)
- 🌐 **Multi-language** — Russian, English, or auto-detect
- 🍔 **Menu bar app** — no Dock icon, no clutter

## Requirements

- macOS 14 or later (tested on 15.7)
- Apple Silicon recommended (Metal); Intel works via Accelerate, slower
- Xcode 16+ to build from source

## Install

### Option 1 — Prebuilt DMG (recommended)

1. Download the latest `OpenVoice.dmg` from [Releases](https://github.com/dnsndrv/OpenVoice/releases).
2. Open the DMG and drag `OpenVoice.app` into `~/Applications`.
3. The app is signed with a self-signed certificate (no Apple Developer ID), so Gatekeeper will block it on first launch. Run this once in Terminal to clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine ~/Applications/OpenVoice.app
```

4. Launch the app. Grant Microphone access when prompted.

### Option 2 — Build from source

```bash
git clone https://github.com/dnsndrv/OpenVoice.git
cd OpenVoice
bash scripts/install.sh
```

The script creates a persistent self-signed certificate in your login keychain, builds the Release configuration, signs the app, and installs it into `~/Applications/OpenVoice.app`. macOS will prompt for your password once (via a GUI dialog) so `codesign` can use the key.

Why a persistent certificate? macOS TCC ties Microphone/Accessibility permissions to the codesign identity. Ad-hoc signing produces a fresh hash on every build, so permissions get revoked. With a stable cert, you grant permissions once and they stick across rebuilds.

## First-run setup

1. **Microphone**: macOS will ask. Click *Allow*.
2. **Accessibility**: open the menu bar icon → *Settings* → *Permissions* → *Open Settings…* → drag `OpenVoice.app` into the Accessibility list. This is required so OpenVoice can capture global hotkeys and synthesize ⌘V.
3. **Whisper model**: open the menu bar icon → *Settings* → *Model* → choose `small` (~460 MB) or `medium` (~1.4 GB) → *Download*. Models are cached in `~/Library/Application Support/OpenVoice/models/`.

After that, place your cursor in any text field, press right ⌘, talk, press right ⌘ again. Your text shows up.

## Usage tips

- **Custom Dictionary** (menu bar → *Dictionary*): teach OpenVoice to fix mishearings consistently. Each entry is a *heard → replace with* pair with optional case sensitivity. Useful for proper nouns, acronyms, and technical terms.
- **Recording state**: the bottom-of-screen pill shows live audio level, timer and transcription progress. It hides automatically the moment Whisper finishes; pasting happens in the background.
- **Languages**: `Settings → Language` lets you pick Russian, English, or `Auto`. Auto detection adds a small overhead but works well across languages.

## Architecture

```
OpenVoice/
├── App/                    # AppDelegate, AppCoordinator (DI root)
├── Audio/                  # AVAudioEngine + AVAudioConverter → 16 kHz mono PCM
├── Transcription/          # WhisperBridge (C API), WhisperTranscriber (actor)
├── Injection/              # NSPasteboard + CGEvent ⌘V
├── Hotkey/                 # CGEventTap, single-modifier detection
├── Coordinator/            # State machine: idle → recording → transcribing → idle
├── Model/                  # SwiftData history, ModelManager, CustomDictionary
├── Settings/               # SettingsStore (@AppStorage)
└── UI/                     # Menu bar, HUD (liquid glass), windows

Packages/Whisper/           # Local SPM package: whisper.cpp v1.7.0 + Metal target
```

The `Packages/Whisper` package vendors whisper.cpp without `unsafeFlags` (the upstream `Package.swift` uses them, which Xcode forbids in app targets). Objective-C and C/C++ are split into two SPM targets so the Metal backend can use manual reference counting (`-fno-objc-arc`) without affecting the rest.

## License

OpenVoice is [MIT licensed](LICENSE).

Bundled dependencies:
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — MIT — see `Packages/Whisper/LICENSE`.
- Whisper models from [HuggingFace ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) — MIT.

## Contributing

Issues and PRs welcome. The codebase is small and the architecture is documented in the section above. A few notes:

- Keep the deployment target at macOS 14 or above.
- Test microphone permission flows on a fresh user account if you change anything in `AudioRecorder` or entitlements.
- TCC is finicky — see comments in `scripts/install.sh` for why we use a persistent self-signed certificate.

## Acknowledgements

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov — the core that makes this possible.
- [VoiceInk](https://github.com/Beingpax/VoiceInk) — UI/UX inspiration (separate codebase, GPL).
