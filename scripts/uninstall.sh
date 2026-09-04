#!/bin/bash
# 停止并移除 Touch Bar 助手（不影响 ZCode 插件本身，可在插件管理里单独禁用/卸载）。
set -euo pipefail

STATE_DIR="${ZCODE_TOUCHBAR_STATE_DIR:-$HOME/Library/Application Support/zcode-touchbar}"
LABEL="com.zpy.zcode-touchbar.agent"
LAUNCH_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_N="$(id -u)"

echo "==> 停止助手"
launchctl bootout "gui/$UID_N" "$LAUNCH_PLIST" 2>/dev/null || true
rm -f "$LAUNCH_PLIST"

echo "==> 删除编译产物"
rm -rf "$HOME/Applications/ZCodeTouchBarAgent.app"
rm -rf "$STATE_DIR/ZCodeTouchBarAgent.app"  # 旧版本安装位置

# 清理残留的请求/响应状态，避免下次启动助手显示过期询问
rm -f "$STATE_DIR/request.json" "$STATE_DIR/ack.json" "$STATE_DIR/response.json"

echo "==> 完成。日志保留在 $STATE_DIR/agent.log"
