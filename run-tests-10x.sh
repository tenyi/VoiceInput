#!/bin/bash
set -o pipefail

echo "=================================================="
echo "開始執行 10 次完整測試套件穩定性驗證..."
echo "=================================================="

for i in {1..10}
do
    echo ""
    echo "--------------------------------------------------"
    echo "第 $i/10 輪測試開始..."
    echo "--------------------------------------------------"
    
    # 執行 xcodebuild test，若失敗立即結束
    if ! xcodebuild test -project VoiceInput.xcodeproj -scheme VoiceInput -destination 'platform=macOS'; then
        echo ""
        echo "❌ 錯誤：第 $i/10 輪測試失敗！穩定性驗證中斷。"
        exit 1
    fi
    
    echo "✅ 第 $i/10 輪測試成功！"
done

echo ""
echo "=================================================="
echo "🎉 恭喜！10/10 輪完整測試套件全部成功通過，無 flaky 測試！"
echo "=================================================="
exit 0
