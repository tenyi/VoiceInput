import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject var viewModel: VoiceInputViewModel
    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "model.engine.picker"), selection: Binding(
                    get: { viewModel.currentSpeechEngine },
                    set: { viewModel.selectedSpeechEngine = $0.rawValue }
                )) {
                    ForEach(SpeechRecognitionEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
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
                        VStack(spacing: 12) {
                            // 進度條
                            ProgressView(value: modelManager.modelImportProgress) {
                                Text(String(localized: "model.import.importing"))
                                    .font(.headline)
                            }
                            .progressViewStyle(.linear)

                            // 進度百分比
                            Text("\(Int(modelManager.modelImportProgress * 100))%")
                                .font(.title2)
                                .fontWeight(.medium)

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
                        .padding(.vertical, 8)
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
                        VStack(spacing: 8) {
                            Image(systemName: "cube.box")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(String(localized: "model.import.empty"))
                                .foregroundColor(.secondary)
                            Text(String(localized: "model.import.hint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
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

                    // 導入按鈕
                    Button(action: {
                        modelManager.importModel()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(String(localized: "model.import.button"))
                        }
                    }
                    .disabled(modelManager.isImportingModel)
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
        .padding()
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
            // 模型圖示
            Image(systemName: "cpu.fill")
                .font(.title2)
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // 模型名稱和類型標籤
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.body)
                        .fontWeight(.medium)

                    // 模型類型標籤
                    Text(model.inferredModelType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
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
                    .foregroundColor(.green)
                    .font(.title3)
            }

            // 在 Finder 中顯示
            Button(action: onShowInFinder) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "model.row.showInFinder"))

            // 刪除按鈕
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help(String(localized: "model.row.delete"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

