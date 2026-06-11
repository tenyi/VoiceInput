#!/bin/bash
# ==============================================================================
# scripts/download-whisper.sh
# 
# 目的: 自動下載與配置專案編譯所必需的 whisper.xcframework
# 使用方式: ./scripts/download-whisper.sh [版本號，預設為 1.7.1]
# ==============================================================================

set -e

# 切換到專案根目錄
cd "$(dirname "$0")/.."

# 版本號，預設使用 1.7.1
VERSION="${1:-1.7.1}"
FRAMEWORK_NAME="whisper.xcframework"

echo "================================================================================"
echo "🔍 正在檢查 ${FRAMEWORK_NAME} 的狀態..."
echo "================================================================================"

if [ -d "${FRAMEWORK_NAME}" ]; then
    echo "✅ ${FRAMEWORK_NAME} 已經存在，跳過下載。"
    exit 0
fi

ZIP_FILE="whisper-v${VERSION}-xcframework.zip"
DOWNLOAD_URL="https://github.com/ggml-org/whisper.cpp/releases/download/v${VERSION}/${ZIP_FILE}"

echo "📥 準備自 GitHub Releases 下載 ${FRAMEWORK_NAME} (版本 v${VERSION})..."
echo "🔗 下載網址: ${DOWNLOAD_URL}"

# 執行下載
if ! curl -L --fail -o "${ZIP_FILE}" "${DOWNLOAD_URL}"; then
    echo "❌ 錯誤: 下載失敗！請檢查您的網路連線或版本號是否正確。"
    echo "💡 您也可以手動從 https://github.com/ggml-org/whisper.cpp/releases 下載，並解壓縮至專案根目錄。"
    exit 1
fi

echo "📦 下載完成。正在解壓縮檔案..."
# 解壓縮檔案，-o 參數代表直接覆寫已存在檔案，-q 代表靜音模式
unzip -o -q "${ZIP_FILE}" -d .

# 確認解壓後是否存在 framework
if [ -d "${FRAMEWORK_NAME}" ]; then
    echo "🎉 ${FRAMEWORK_NAME} 下載與配置成功！"
else
    echo "⚠️ 警告: 解壓成功但未在預期位置發現 ${FRAMEWORK_NAME}。"
    # 有些舊版本 zip 包裝可能內含多一層子目錄，我們來移動它
    if [ -d "whisper-v${VERSION}-xcframework/${FRAMEWORK_NAME}" ]; then
        mv "whisper-v${VERSION}-xcframework/${FRAMEWORK_NAME}" .
        rm -rf "whisper-v${VERSION}-xcframework"
        echo "🎉 已從子目錄提取並成功配置 ${FRAMEWORK_NAME}！"
    else
        echo "❌ 錯誤: 找不到 ${FRAMEWORK_NAME}，請手動確認解壓內容。"
        exit 1
    fi
fi

# 清理下載的壓縮檔
rm -f "${ZIP_FILE}"
echo "🧹 已清理臨時檔案。"
echo "================================================================================"
exit 0
