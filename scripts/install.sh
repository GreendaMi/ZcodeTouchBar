#!/bin/bash
# 编译 Touch Bar 助手并注册为 LaunchAgent。
# 用法: bash scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${ZCODE_TOUCHBAR_STATE_DIR:-$HOME/Library/Application Support/zcode-touchbar}"
# 装到 ~/Applications：用户可见（访达/启动台），而状态与日志仍在 Application Support
APP_DIR="$HOME/Applications/ZCodeTouchBarAgent.app"
BIN="$APP_DIR/Contents/MacOS/ZCodeTouchBarAgent"
LABEL="com.zpy.zcode-touchbar.agent"
LAUNCH_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$STATE_DIR/agent.log"
UID_N="$(id -u)"

echo "==> 创建目录"
mkdir -p -m 700 "$STATE_DIR" "$APP_DIR/Contents/MacOS" "$HOME/Applications" "$HOME/Library/LaunchAgents"
# 迁移：清掉旧版本（曾装在 Application Support 里，用户不可见）
rm -rf "$STATE_DIR/ZCodeTouchBarAgent.app"

echo "==> swiftc 编译 Touch Bar 助手…"
swiftc -O -o "$BIN" "$ROOT/agent/TouchBarAgent.swift"

echo "==> 生成应用图标"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
swiftc -O "$ROOT/scripts/make-icon.swift" -o "$STATE_DIR/.make-icon"
"$STATE_DIR/.make-icon" "$ICONSET_DIR" "$ROOT/assets/icon.png"
mkdir -p "$APP_DIR/Contents/Resources"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -f "$STATE_DIR/.make-icon"

cat > "$APP_DIR/Contents/Info.plist" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.zpy.zcode-touchbar.agent</string>
  <key>CFBundleName</key>
  <string>ZCodeTouchBarAgent</string>
  <key>CFBundleExecutable</key>
  <string>ZCodeTouchBarAgent</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
XML

echo "==> 注册 LaunchAgent（登录自启）"
launchctl bootout "gui/$UID_N" "$LAUNCH_PLIST" 2>/dev/null || true
sed -e "s|@AGENT_BIN@|$BIN|g" -e "s|@LOG_PATH@|$LOG_PATH|g" \
    "$ROOT/agent/com.zpy.zcode-touchbar.agent.plist" > "$LAUNCH_PLIST"
launchctl bootstrap "gui/$UID_N" "$LAUNCH_PLIST"

sleep 1
if launchctl print "gui/$UID_N/$LABEL" >/dev/null 2>&1; then
  if grep -q "Touch Bar 私有 API 不可用" "$LOG_PATH" 2>/dev/null; then
    echo "!! 助手检测到本机 Touch Bar 私有 API 不可用（无 Touch Bar 硬件或系统已移除）。"
    echo "!! 插件仍可安全安装，但只会走 ZCode 原生询问流程。"
  else
    echo "==> 助手已运行。菜单栏出现问号气泡图标即代表正常。"
  fi
else
  echo "!! LaunchAgent 启动失败，请查看日志: $LOG_PATH"
  exit 1
fi

cat <<EOF

下一步：安装 ZCode 插件（若尚未安装）
  1. 打开 ZCode → 设置 → 插件管理 → 市场/发现页 → 「+」添加本地市场
  2. 选择目录: $ROOT
  3. 安装列表中的 zcode-touchbar，重启 ZCode 会话

验证:
  bash $ROOT/scripts/test-question.sh     # Touch Bar 应点亮显示选项，点选后终端打印决策 JSON
  bash $ROOT/scripts/test-permission.sh   # Touch Bar 应显示 允许/拒绝

卸载:
  bash $ROOT/scripts/uninstall.sh
EOF
