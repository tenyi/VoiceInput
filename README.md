# VoiceInput

VoiceInput is a macOS voice input tool that lets you dictate text into any application. Inspired by [VoiceInk](https://github.com/Beingpax/VoiceInk), this tool is completely free and open, with no license required.

## Features

- **Push-to-talk**: Use modifier keys (Command, Option, Fn) as hotkeys — hold to record, release to transcribe and insert text into the focused input field
- **Real-time recognition**: Live transcription results displayed while recording
- **Multi-language support**: Traditional Chinese, Simplified Chinese, English, Japanese
- **Flexible settings**: Customizable hotkey, language, and auto-insert toggle
- **Floating panel**: A sleek floating capsule window displayed during recording
- **LLM smart correction**: Built-in language model pipeline to automatically fix typos and awkward phrasing
- **Custom dictionary**: Personalized word replacement rules (e.g., replace "water level center" with "horizontally centered")

## Supported Hotkeys

| Hotkey | Description |
|--------|-------------|
| Right Command (⌘) | Default hotkey |
| Left Command (⌘) | |
| Right Option (⌥) | |
| Left Option (⌥) | |
| Fn key | |

## System Requirements

- macOS 12.0 or later
- Microphone permission
- Speech recognition permission
- Accessibility permission (for simulating keyboard input)

## Permissions

On first launch, the system will prompt you to grant the following permissions:

1. **Microphone**: To record your voice
2. **Speech Recognition**: To convert speech to text
3. **Accessibility**: To insert text into other applications

## Installation

### Build from Source

1. Clone the repository:

   ```bash
   git clone https://github.com/tenyi/VoiceInput.git
   cd VoiceInput
   ```

2. Open `VoiceInput.xcodeproj` in Xcode

3. Configure your developer signing in Xcode

4. Build and run (⌘R)

### Configure Permissions

1. On first launch, a permission dialog will appear — click "Allow"
2. If permission is denied, go to **System Preferences > Privacy & Security** to enable manually
3. Click the VoiceInput icon in the menu bar and select "Settings" to check permission status

## Usage

### Basic Operation

1. **Start recording**: Hold the configured hotkey (e.g., Right Command or Fn)
2. **Speak**: Talk into your microphone
3. **Stop and insert**: Release the hotkey — your speech is automatically converted to text and inserted into the active input field

### Settings

1. Click the VoiceInput icon in the menu bar
2. Select "Settings" to open the settings window
3. You can configure:
   - **Recognition language**: Choose the language for speech recognition
   - **Hotkey**: Choose the key to trigger recording
   - **Auto-insert**: Toggle whether text is automatically inserted after transcription

## Technical Architecture

- **Speech recognition**:
  - **Apple Speech Framework**: Built-in macOS speech recognition, works out of the box
  - **Whisper**: Local Whisper model support for offline use with better accuracy
- **Audio processing**: AVAudioEngine for recording
- **Keyboard simulation**: CGEvent to simulate Cmd+V paste
- **Hotkey monitoring**: CGEventTap to listen for keyboard events

## Recommended Model

### MediaTek Breeze ASR (Highly recommended for Traditional Chinese)

For Traditional Chinese recognition, we recommend the Breeze ASR model by MediaTek:

**Download**: <https://huggingface.co/alan314159/Breeze-ASR-25-whispercpp/tree/main>

**Recommended versions**:

- `ggml-model-q4_k.bin` (4-bit quantized): Best balance of size and accuracy — recommended first choice
- `ggml-model-q8_k.bin` (8-bit quantized): For higher accuracy when disk space allows

**How to use**:

1. Download `ggml-model-q4_k.bin` from the link above
2. Open VoiceInput settings
3. Go to the "Model" tab
4. Click "Import Model" and select the downloaded file
5. Select the model as the Whisper engine

**Why Breeze ASR**:

- Designed specifically for Chinese speech — excellent Traditional Chinese accuracy
- Optimized for whisper.cpp, runs efficiently on Apple Silicon
- 4-bit quantized version is compact (~900 MB) with low memory footprint

## LLM Smart Correction & Custom Dictionary

In addition to local speech recognition, VoiceInput supports powerful post-processing features for more accurate input:

### LLM Correction

Configure an OpenAI-compatible API endpoint (supports official OpenAI, OpenRouter, and custom providers) to let a language model automatically correct transcription errors.

**💡 Strongly recommended: `google/gemini-2.5-flash-lite`**:

- **Ultra-fast**: Minimal latency added by the correction step
- **Very affordable**: Extremely low API cost — perfect for heavy daily voice input

### Custom Dictionary (User Dictionary)

In the "Dictionary" tab of settings, add your own word replacement rules. The custom dictionary is applied before final text output, ensuring your proper nouns and specific terminology are always correct.

## Author

- Tenyi

## License

This project is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
