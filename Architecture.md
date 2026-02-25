# VoiceInput 系統架構說明

**分析日期：** 2026-02-25

---

## 一、系統概覽

VoiceInput 是一個 macOS MenuBar App，核心功能為：監聽全域快捷鍵 → 錄製麥克風音訊 → 語音轉文字 → (可選 LLM 修正) → 自動插入到前景應用程式。

整體採用 **SwiftUI + MVVM + Protocol-Oriented** 架構，搭配大量 **依賴注入 (DI)** 以便單元測試。

---

## 二、系統分層架構圖

```mermaid
flowchart TB
    subgraph UI["🖥️ UI 層 (SwiftUI Views)"]
        direction LR
        MenuBar["MenuBarExtra\n(VoiceInputApp)"]
        ContentView["ContentView\n(主控/歷史)"]
        Settings["SettingsView\n(設定視窗)"]
        Floating["FloatingPanelView\n(浮動狀態面板)"]
        SubSettings["GeneralSettingsView\nTranscriptionSettingsView\nModelSettingsView\nLLMSettingsView\nDictionarySettingsView\nHistorySettingsView"]
    end

    subgraph VM["🧠 ViewModel 層 (ObservableObject)"]
        direction LR
        VVM["VoiceInputViewModel\n⟨@MainActor⟩"]
        LLMVM["LLMSettingsViewModel"]
        MM["ModelManager\n⟨@MainActor⟩"]
        HM["HistoryManager\n⟨@MainActor⟩"]
    end

    subgraph BL["⚙️ 業務邏輯層 (Managers & Controllers)"]
        direction LR
        HIC["HotkeyInteractionController\n(快捷鍵策略)"]
        TM["TranscriptionManager\n(轉錄協調)"]
        PM["PermissionManager\n(權限管理)"]
        DM["DictionaryManager\n(字詞置換)"]
        WM["WindowManager\n(視窗管理)"]
        LLMPS["LLMProcessingService\n(LLM 處理)"]
    end

    subgraph SVC["🔧 服務層 (Protocol + 實作)"]
        direction LR
        AE["AudioEngine\n(音訊錄製)"]
        HKM["HotkeyManager\n(全域快捷鍵)"]
        IS["InputSimulator\n(鍵盤模擬)"]
        SFS["SFSpeechTranscriptionService\n(Apple 辨識)"]
        WTS["WhisperTranscriptionService\n(本地 Whisper)"]
        LLMS["LLMService\n(LLM API 呼叫)"]
    end

    subgraph INF["🗄️ 基礎層 (Infrastructure)"]
        direction LR
        KH["KeychainHelper\n(金鑰儲存)"]
        DFS["DefaultFileSystem\n(檔案系統)"]
        URLSess["URLSession\n(網路)"]
        LibW["LibWhisper / whisper.xcframework\n(Whisper C API)"]
    end

    UI -->|environmentObject / @EnvironmentObject| VM
    VM --> BL
    BL --> SVC
    SVC --> INF
    WM -->|建立 NSPanel| Floating
```

---

## 三、核心類別關係圖

### 3-1 VoiceInputViewModel 核心依賴

```mermaid
classDiagram
    class VoiceInputViewModel {
        <<MainActor, ObservableObject>>
        +appState: AppState
        +transcribedText: String
        +selectedLanguage: String
        +autoInsertText: Bool
        +selectedHotkey: String
        +recordingTriggerMode: String
        -hotkeyController: HotkeyInteractionController
        -cancellables: Set~AnyCancellable~
        +startRecording()
        +stopRecordingAndTranscribe()
        +performLLMCorrection()
        +toggleRecording()
        +updateHotkey(HotkeyOption)
        +updateRecordingTriggerMode(RecordingTriggerMode)
    }

    class HotkeyInteractionController {
        +mode: RecordingTriggerMode
        +isRecording: Bool
        +onStartRecording: Closure
        +onStopAndTranscribe: Closure
        +hotkeyPressed()
        +hotkeyReleased()
    }

    class TranscriptionManager {
        <<ObservableObject>>
        +transcribedText: String
        +isTranscribing: Bool
        +textProcessor: Closure
        +configure(engine:modelURL:language:)
        +startTranscription()
        +stopTranscription()
        +processAudioBuffer(AVAudioPCMBuffer)
    }

    class AudioEngineProtocol {
        <<protocol>>
        +isRecording: Bool
        +permissionGranted: Bool
        +availableInputDevices: [AudioInputDevice]
        +startRecording(callback:)
        +stopRecording()
    }

    class HotkeyManagerProtocol {
        <<protocol>>
        +currentHotkey: HotkeyOption
        +onHotkeyPressed: Closure
        +onHotkeyReleased: Closure
        +setHotkey(HotkeyOption)
        +startMonitoring()
    }

    class InputSimulatorProtocol {
        <<protocol>>
        +insertText(String)
        +checkAccessibilityPermission(showAlert:) Bool
    }

    class PermissionManager {
        <<ObservableObject, Singleton>>
        +microphoneStatus: PermissionStatus
        +speechRecognitionStatus: PermissionStatus
        +accessibilityStatus: PermissionStatus
        +checkAllPermissions()
        +requestAllPermissionsIfNeeded()
    }

    class WindowManager {
        <<Singleton>>
        +viewModel: VoiceInputViewModel
        +showFloatingWindow(isRecording:)
        +hideFloatingWindow()
    }

    VoiceInputViewModel *-- HotkeyInteractionController : owns
    VoiceInputViewModel *-- TranscriptionManager : owns
    VoiceInputViewModel --> AudioEngineProtocol : inject
    VoiceInputViewModel --> HotkeyManagerProtocol : inject
    VoiceInputViewModel --> InputSimulatorProtocol : inject
    VoiceInputViewModel --> PermissionManager : uses
    VoiceInputViewModel --> WindowManager : uses
```

### 3-2 轉錄服務層

```mermaid
classDiagram
    class TranscriptionServiceProtocol {
        <<protocol>>
        +onTranscriptionResult: Callback
        +start()
        +stop()
        +process(buffer: AVAudioPCMBuffer)
    }

    class SFSpeechTranscriptionService {
        -speechRecognizer: SFSpeechRecognizer
        -recognitionTask: SFSpeechRecognitionTask
        -audioBuffer: [AVAudioPCMBuffer]
        +updateLocale(identifier: String)
    }

    class WhisperTranscriptionService {
        <<MainActor>>
        -whisperContext: WhisperContext
        -accumulatedBuffer: [Float]
        -audioProcessingQueue: DispatchQueue
        -isRunning: Bool
        -isTranscribing: Bool
        -transcribeChunkIfNeeded() async
        -transcribeFinalIfNeeded() async
        -convertTo16kHz(buffer:) [Float]
    }

    class WhisperContext {
        -ctx: OpaquePointer
        +transcribe(samples:[Float], language:String) async String
    }

    class TranscriptionManager {
        -transcriptionService: TranscriptionServiceProtocol
        -currentConfig: TranscriptionConfig
        +textProcessor: Closure
        +configure(engine:modelURL:language:)
    }

    class TranscriptionConfig {
        <<struct>>
        +engine: SpeechRecognitionEngine
        +modelPath: String
        +language: String
    }

    TranscriptionManager --> TranscriptionServiceProtocol : uses
    SFSpeechTranscriptionService ..|> TranscriptionServiceProtocol
    WhisperTranscriptionService ..|> TranscriptionServiceProtocol
    WhisperTranscriptionService --> WhisperContext : owns
    TranscriptionManager --> TranscriptionConfig : uses
```

### 3-3 LLM 服務層

```mermaid
classDiagram
    class LLMSettingsViewModel {
        <<ObservableObject>>
        +llmEnabled: Bool
        +llmProvider: String
        +llmAPIKey: String
        +llmModel: String
        +llmPrompt: String
        +customProviders: [CustomLLMProvider]
        +resolveEffectiveConfiguration() EffectiveLLMConfiguration
        +loadAPIKey(for:customId:)
        +addCustomProvider()
        +removeCustomProvider()
    }

    class LLMProcessingService {
        <<Singleton>>
        +process(text:config:logger:completion:)
    }

    class LLMService {
        <<Singleton>>
        -networkProvider: NetworkProviderProtocol
        +correctText(text:prompt:provider:apiKey:url:model:) async
        -callOpenAI() async String
        -callAnthropic() async String
        -callOllama() async String
        -callCustomAPI() async String
        -parseOpenAILikeResponse(data:) String
        -parseAnthropicResponse(data:) String
    }

    class NetworkProviderProtocol {
        <<protocol>>
        +data(for: URLRequest) async (Data, URLResponse)
    }

    class KeychainHelper {
        <<Singleton>>
        +save(_:service:account:)
        +read(service:account:) String?
        +delete(service:account:)
    }

    class EffectiveLLMConfiguration {
        <<struct>>
        +prompt: String
        +provider: LLMProvider
        +apiKey: String
        +url: String
        +model: String
    }

    class CustomLLMProvider {
        <<struct>>
        +id: UUID
        +name: String
        +url: String
        +model: String
        +prompt: String
    }

    LLMSettingsViewModel --> KeychainHelper : saves API key
    LLMSettingsViewModel --> CustomLLMProvider : manages
    LLMSettingsViewModel --> EffectiveLLMConfiguration : produces
    LLMProcessingService --> LLMService : delegates
    LLMService --> NetworkProviderProtocol : inject
    LLMService --> EffectiveLLMConfiguration : consumes
```

### 3-4 Model 與 History 管理

```mermaid
classDiagram
    class ModelManager {
        <<MainActor, ObservableObject>>
        +importedModels: [ImportedModel]
        +whisperModelPath: String
        +isImportingModel: Bool
        +modelImportProgress: Double
        +modelsDirectory: URL
        +importModel()
        +importModelFromURL(URL)
        +deleteModel(ImportedModel)
        +selectModel(ImportedModel)
        +getSelectedModelURL() URL?
    }

    class ImportedModel {
        <<struct, Codable>>
        +id: UUID
        +name: String
        +fileName: String
        +fileSize: Int64?
        +importDate: Date
        +fileSizeFormatted: String
        +inferredModelType: String
        +fileExists(in:) Bool
    }

    class HistoryManager {
        <<MainActor, ObservableObject>>
        +transcriptionHistory: [TranscriptionHistoryItem]
        +addHistoryIfNeeded(String)
        +deleteHistoryItem(TranscriptionHistoryItem)
        +copyHistoryText(String)
    }

    class TranscriptionHistoryItem {
        <<struct, Codable>>
        +id: UUID
        +text: String
        +createdAt: Date
    }

    class FileSystemProtocol {
        <<protocol>>
        +fileExists(atPath:) Bool
        +data(contentsOf:) Data
        +createDirectory(at:withIntermediateDirectories:)
        +write(_:to:options:)
        +removeItem(at:)
        +copyItem(at:to:)
        +getFileSize(at:) Int64
    }

    class DefaultFileSystem {
        <<Singleton>>
        -manager: FileManager
    }

    ModelManager --> FileSystemProtocol : inject
    ModelManager --> ImportedModel : manages
    HistoryManager --> FileSystemProtocol : inject
    HistoryManager --> TranscriptionHistoryItem : manages
    DefaultFileSystem ..|> FileSystemProtocol
```

---

## 四、協議與實作對應圖

```mermaid
classDiagram
    direction LR

    class AudioEngineProtocol { <<protocol>> }
    class HotkeyManagerProtocol { <<protocol>> }
    class InputSimulatorProtocol { <<protocol>> }
    class TranscriptionServiceProtocol { <<protocol>> }
    class FileSystemProtocol { <<protocol>> }
    class NetworkProviderProtocol { <<protocol>> }
    class KeychainProtocol { <<protocol>> }

    class AudioEngine { <<Singleton>> }
    class HotkeyManager { <<Singleton>> }
    class InputSimulator { <<Singleton>> }
    class SFSpeechTranscriptionService { }
    class WhisperTranscriptionService { }
    class DefaultFileSystem { <<Singleton>> }
    class URLSession { <<System>> }
    class KeychainHelper { <<Singleton>> }

    class MockAudioEngine { <<Test Mock>> }
    class MockHotkeyManager { <<Test Mock>> }
    class MockInputSimulator { <<Test Mock>> }
    class MockNetworkProvider { <<Test Mock>> }
    class MockFileSystem { <<Test Mock>> }

    AudioEngine ..|> AudioEngineProtocol
    MockAudioEngine ..|> AudioEngineProtocol

    HotkeyManager ..|> HotkeyManagerProtocol
    MockHotkeyManager ..|> HotkeyManagerProtocol

    InputSimulator ..|> InputSimulatorProtocol
    MockInputSimulator ..|> InputSimulatorProtocol

    SFSpeechTranscriptionService ..|> TranscriptionServiceProtocol
    WhisperTranscriptionService ..|> TranscriptionServiceProtocol

    DefaultFileSystem ..|> FileSystemProtocol
    MockFileSystem ..|> FileSystemProtocol

    URLSession ..|> NetworkProviderProtocol
    MockNetworkProvider ..|> NetworkProviderProtocol

    KeychainHelper ..|> KeychainProtocol
```

---

## 五、錄音到輸入的完整序列圖

```mermaid
sequenceDiagram
    actor User as 使用者
    participant HKM as HotkeyManager
    participant HIC as HotkeyInteractionController
    participant VVM as VoiceInputViewModel
    participant AE as AudioEngine
    participant TM as TranscriptionManager
    participant WTS as WhisperTranscriptionService
    participant LLM as LLMService
    participant IS as InputSimulator
    participant WM as WindowManager

    User->>HKM: 按下快捷鍵 (fn/Cmd/Option)
    HKM->>HKM: processFlagsChangedEvent()
    HKM->>HIC: onHotkeyPressed()

    alt pressAndHold 模式
        HIC->>VVM: onStartRecording()
    else toggle 模式（閒置中）
        HIC->>VVM: onStartRecording()
    end

    VVM->>TM: configure(engine:whisper, modelURL:, language:)
    VVM->>WM: showFloatingWindow(isRecording: true)
    WM-->>User: 顯示浮動面板（錄音中🎙️）
    VVM->>TM: startTranscription()
    VVM->>AE: startRecording(callback:)
    AE-->>VVM: 開始產生 AVAudioPCMBuffer

    loop 錄音期間每 1 秒
        AE->>TM: processAudioBuffer(buffer)
        TM->>WTS: process(buffer:)
        WTS->>WTS: convertTo16kHz()
        WTS->>WTS: transcribeChunkIfNeeded()
        WTS-->>TM: onTranscriptionResult(.success(partialText))
        TM->>TM: textProcessor（簡轉繁 + 字典）
        TM-->>VVM: $transcribedText 更新
        VVM-->>User: 浮動面板顯示即時文字
    end

    User->>HKM: 放開快捷鍵（或再按一次）
    HKM->>HIC: onHotkeyReleased()
    HIC->>VVM: onStopAndTranscribe()

    VVM->>AE: stopRecording()
    VVM->>TM: stopTranscription()
    VVM->>WM: showFloatingWindow(isRecording: false)
    WM-->>User: 浮動面板（轉寫中⟳）

    WTS->>WTS: transcribeFinalIfNeeded()
    WTS-->>TM: onTranscriptionResult(.success(finalText))
    TM-->>VVM: $transcribedText 最終文字

    alt llmEnabled == true
        VVM->>LLM: correctText(text:, provider:, apiKey:...)
        LLM-->>VVM: correctedText
        VVM->>VVM: toTraditionalChinese() + replaceText()
        VVM-->>User: 浮動面板（增強中⚡）
    end

    VVM->>VVM: addHistoryIfNeeded()

    alt autoInsertText == true
        VVM->>IS: insertText(transcribedText)
        IS->>IS: pasteText() → Cmd+V 模擬
        IS-->>User: 文字插入到前景 App
    end

    VVM->>WM: hideFloatingWindow()
    WM-->>User: 浮動面板隱藏
```

---

## 六、快捷鍵狀態機

```mermaid
stateDiagram-v2
    [*] --> Idle : App 啟動

    state "pressAndHold 模式" as PAH {
        [*] --> PAH_Idle
        PAH_Idle --> PAH_Recording : hotkeyPressed()\n→ onStartRecording()
        PAH_Recording --> PAH_Idle : hotkeyReleased()\n→ onStopAndTranscribe()
        note right of PAH_Recording : 防抖：< 300ms 忽略放開
    }

    state "toggle 模式" as TGL {
        [*] --> TGL_Idle
        TGL_Idle --> TGL_Transitioning1 : hotkeyPressed()
        TGL_Transitioning1 --> TGL_Recording : 300ms debounce 完成\n→ onStartRecording()
        TGL_Recording --> TGL_Transitioning2 : hotkeyPressed()
        TGL_Transitioning2 --> TGL_Idle : 300ms debounce 完成\n→ onStopAndTranscribe()
        TGL_Transitioning1 --> TGL_Transitioning1 : 防重入：忽略快速連擊
        TGL_Transitioning2 --> TGL_Transitioning2 : 防重入：忽略快速連擊
    }

    state "AppState 主狀態機" as APPSTATE {
        [*] --> idle
        idle --> recording : startRecording()
        recording --> transcribing : stopRecordingAndTranscribe()
        transcribing --> enhancing : llmEnabled == true
        transcribing --> idle : llmEnabled == false\n(隱藏視窗)
        enhancing --> idle : LLM 完成\n(隱藏視窗)
        recording --> idle : 錄音失敗\n(2s 後恢復)
    }
```

---

## 七、LLM Provider 選擇流程

```mermaid
flowchart TD
    A[使用者開啟 LLM 設定] --> B{選擇 Provider}

    B --> C[OpenAI]
    B --> D[Anthropic]
    B --> E[Ollama]
    B --> F[自訂 Provider]

    C --> C1[輸入 API Key\n儲存到 Keychain]
    C --> C2[設定模型名稱\ngpt-4o-mini 預設]

    D --> D1[輸入 API Key\n儲存到 Keychain]
    D --> D2[設定模型名稱\nclaude-3-haiku 預設]

    E --> E1[設定 URL\nlocalhost:11434 預設]
    E --> E2[設定模型名稱\nllama3 預設]

    F --> F1[新增 CustomLLMProvider\n{名稱, URL, 模型, Prompt}]
    F --> F2[API Key 存入 Keychain\n以 UUID 為 account key]

    C1 & C2 & D1 & D2 & E1 & E2 & F1 & F2 --> G[resolveEffectiveConfiguration()]

    G --> H[EffectiveLLMConfiguration\n{prompt, provider, apiKey, url, model}]

    H --> I[LLMProcessingService.process()]
    I --> J[LLMService.correctText()]

    J --> K{provider}
    K --> L[callOpenAI\nPOST api.openai.com]
    K --> M[callAnthropic\nPOST api.anthropic.com]
    K --> N[callOllama\nPOST localhost:11434/v1/chat/completions]
    K --> O[callCustomAPI\nPOST 自訂 URL]

    L & M & N & O --> P[parseResponse]
    P --> Q{成功?}
    Q --> |Yes| R[修正後文字回傳 VoiceInputViewModel]
    Q --> |No| S[LLMServiceError\n→ lastLLMError 顯示於浮動面板]
```

---

## 八、資料持久化策略

```mermaid
flowchart LR
    subgraph UserDefaults["UserDefaults / @AppStorage"]
        UD1["selectedLanguage\n選擇語言"]
        UD2["selectedHotkey\n快捷鍵"]
        UD3["recordingTriggerMode\n觸發模式"]
        UD4["autoInsertText\n自動插入"]
        UD5["selectedSpeechEngine\n語音引擎"]
        UD6["whisperModelPath\n模型路徑"]
        UD7["llmEnabled / llmProvider\nllmModel / llmPrompt\nllmURL"]
        UD8["importedModels (JSON)\n已匯入模型列表"]
        UD9["customProvidersData (JSON)\n自訂 Provider 列表"]
        UD10["builtInProviderSettingsData (JSON)\n內建 Provider 設定"]
    end

    subgraph Keychain["Keychain (KeychainHelper)"]
        KC1["llmAPIKey.OpenAI\nOpenAI API Key"]
        KC2["llmAPIKey.Anthropic\nAnthropic API Key"]
        KC3["llmAPIKey.{UUID}\n自訂 Provider API Key"]
    end

    subgraph File["Application Support 目錄"]
        F1["Models/\n*.bin Whisper 模型檔案"]
        F2["transcription_history.json\n最近 10 筆轉錄記錄"]
    end

    VoiceInputViewModel --> UD1 & UD2 & UD3 & UD4 & UD5
    ModelManager --> UD6 & UD8
    LLMSettingsViewModel --> UD7 & UD9 & UD10
    LLMSettingsViewModel --> KC1 & KC2 & KC3
    ModelManager --> F1
    HistoryManager --> F2
```

---

## 九、架構特色與設計決策摘要

### 協議驅動設計 (Protocol-Oriented Design)
所有核心服務均定義於協議（`AudioEngineProtocol`、`HotkeyManagerProtocol` 等），實際實作與測試 Mock 均實作相同協議。`VoiceInputViewModel` 透過建構子注入，可在測試中替換為 Mock，不需要啟動真正的麥克風或快捷鍵監聽。

### 分層職責分離
| 層次 | 負責範圍 | 代表類別 |
|------|---------|---------|
| UI 層 | 畫面渲染、使用者互動 | `ContentView`、`FloatingPanelView` |
| ViewModel 層 | 應用程式狀態、業務協調 | `VoiceInputViewModel`、`LLMSettingsViewModel` |
| Controller 層 | 單一職責的轉換邏輯 | `HotkeyInteractionController`、`TranscriptionManager` |
| 服務層 | 系統 API 封裝 | `AudioEngine`、`HotkeyManager`、`LLMService` |
| 基礎層 | 平台抽象 | `DefaultFileSystem`、`KeychainHelper` |

### 資料安全策略
- **API Key** 一律存入 **Keychain**，不存於 UserDefaults
- 每個 Provider（包含自訂）以獨立 account key 存儲，互不干擾
- 實際 API 請求前重新從 Keychain 讀取，確保使用最新金鑰

### 並發策略
- `VoiceInputViewModel`、`ModelManager`、`HistoryManager` 標記 `@MainActor`
- `WhisperTranscriptionService` 的音訊處理在獨立 `DispatchQueue` 執行，切回 MainActor 才修改狀態
- `HotkeyManager` 的 CGEventTap callback 透過 `DispatchQueue.main.async` 回到主執行緒

### 快捷鍵架構（三層解耦）
```
CGEventTap（系統層）
    ↓ keyCode + flags
HotkeyManager（訊號層）— 純粹的「按下/放開」事件派送
    ↓ onPressed / onReleased
HotkeyInteractionController（策略層）— 依模式決定語意
    ↓ onStartRecording / onStopAndTranscribe
VoiceInputViewModel（業務層）— 執行錄音流程
```
