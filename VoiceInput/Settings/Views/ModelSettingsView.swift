import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        Form {
            // 頁首卡片
            SettingsPaneHeader(pane: .model)

            Section {
                Picker(selection: Binding(
                    get: { viewModel.currentSpeechEngine },
                    set: { viewModel.selectedSpeechEngine = $0.rawValue }
                )) {
                    ForEach(SpeechRecognitionEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                } label: {
                    SettingsRowLabel(
                        title: String(localized: "model.engine.picker"),
                        symbol: "waveform.badge.mic",
                        tint: .orange
                    )
                }
                .pickerStyle(.segmented)
            } header: {
                Text(String(localized: "model.section.engine"))
            } footer: {
                if viewModel.currentSpeechEngine == .apple {
                    Text(String(localized: "model.engine.apple.footer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(String(localized: "model.engine.whisper.footer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.currentSpeechEngine == .whisper {
                // 匯入進度顯示
                if modelManager.isImportingModel {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(String(localized: "model.import.importing"))
                                    .font(.headline)
                                Spacer()
                                // 進度百分比（等寬數字避免跳動）
                                Text("\(Int(modelManager.modelImportProgress * 100))%")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                            }

                            // 進度條
                            ProgressView(value: modelManager.modelImportProgress)
                                .progressViewStyle(.linear)

                            // 速度和剩餘時間
                            HStack(spacing: 16) {
                                if !modelManager.modelImportSpeed.isEmpty {
                                    Label(modelManager.modelImportSpeed, systemImage: "speedometer")
                                }

                                if !modelManager.modelImportRemainingTime.isEmpty {
                                    Label(modelManager.modelImportRemainingTime, systemImage: "clock")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(String(localized: "model.section.importProgress"))
                    }
                }

                // 錯誤訊息顯示
                if let error = modelManager.modelImportError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.callout)
                    } header: {
                        Text(String(localized: "model.section.error"))
                    }
                }

                // 已導入的模型列表
                Section {
                    if modelManager.importedModels.isEmpty {
                        // 空狀態
                        VStack(spacing: 8) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text(String(localized: "model.import.empty"))
                                .foregroundColor(.secondary)
                            Text(String(localized: "model.import.hint"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        ForEach(modelManager.importedModels, id: \.fileName) { model in
                            ModelRowView(
                                model: model,
                                isSelected: modelManager.whisperModelPath.contains(model.fileName),
                                modelsDirectory: modelManager.modelsDirectory,
                                onSelect: { modelManager.selectModel(model) },
                                onDelete: { modelManager.deleteModel(model) },
                                onShowInFinder: { modelManager.showModelInFinder(model) }
                            )
                        }
                    }

                    // 導入按鈕（靠右對齊，與 macOS 表單慣例一致）
                    HStack {
                        Spacer()
                        Button(action: {
                            modelManager.importModel()
                        }) {
                            Label(String(localized: "model.import.button"), systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(modelManager.isImportingModel)
                    }
                } header: {
                    HStack {
                        Text(String(localized: "model.section.importedModels"))
                        Spacer()
                        if !modelManager.importedModels.isEmpty {
                            Text(String(format: String(localized: "model.import.count"), modelManager.importedModels.count))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text(String(localized: "model.import.footer"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            }
        }
        .formStyle(.grouped)
    }
}

/// 模型列表行視圖
struct ModelRowView: View {
    let model: ImportedModel
    let isSelected: Bool
    let modelsDirectory: URL
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onShowInFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 模型圖示：選中時以綠色強調，未選中為灰色
            SettingsIconBadge(
                symbol: "cube.fill",
                tint: isSelected ? .green : .gray,
                size: 30
            )

            VStack(alignment: .leading, spacing: 4) {
                // 模型名稱和類型標籤
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.body)
                        .fontWeight(.medium)

                    // 模型類型標籤
                    Text(model.inferredModelType)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                // 檔案大小和匯入日期
                HStack(spacing: 8) {
                    // 檔案大小
                    Label(model.fileSizeFormatted, systemImage: "externaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 匯入日期
                    if let importDate = model.importDate as Date? {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(importDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 檔案存在狀態
                if !model.fileExists(in: modelsDirectory) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(String(localized: "model.row.fileNotFound"))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // 選中狀態
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }

            // 在 Finder 中顯示
            Button(action: onShowInFinder) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "model.row.showInFinder"))
            .accessibilityLabel(String(localized: "model.row.showInFinder"))

            // 刪除按鈕
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "model.row.delete"))
            .accessibilityLabel(String(localized: "model.row.delete"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

