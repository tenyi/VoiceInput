#!/bin/bash
# ==============================================================================
# scripts/setup-pre-commit.sh
# 
# 目的: 自動將專案中的 scripts/pre-commit 鉤子安裝至本地的 .git/hooks/ 中，
#      並配置適當的執行權限。
# ==============================================================================

set -e

# 切換到專案根目錄
cd "$(dirname "$0")/.."

HOOK_SOURCE="scripts/pre-commit"
HOOK_DESTINATION=".git/hooks/pre-commit"

echo "================================================================================"
echo "⚙️ 正在安裝 Git pre-commit 安全鉤子..."
echo "================================================================================"

# 檢查 .git 目錄是否存在 (確保是在 Git 專案內執行)
if [ ! -d ".git" ]; then
    echo "❌ 錯誤: 找不到 .git 目錄！請確認您是在 Git 專案根目錄下執行此腳本。"
    exit 1
fi

# 檢查鉤子來源檔案是否存在
if [ ! -f "${HOOK_SOURCE}" ]; then
    echo "❌ 錯誤: 找不到來源檔案 ${HOOK_SOURCE}！"
    exit 1
fi

# 複製並設置權限
echo "📦 正在複製鉤子檔案至 ${HOOK_DESTINATION}..."
cp "${HOOK_SOURCE}" "${HOOK_DESTINATION}"

echo "🔐 正在賦予 ${HOOK_DESTINATION} 執行權限 (chmod +x)..."
chmod +x "${HOOK_DESTINATION}"

# 同時確保專案內的 scripts/pre-commit 也是可執行的
chmod +x "${HOOK_SOURCE}"

echo "🎉 Git pre-commit 安全鉤子安裝成功！"
echo "💡 現在，每次執行 'git commit' 時皆會自動檢查暫存檔案的大小與敏感資訊。"
echo "================================================================================"
exit 0
