#!/bin/bash
# ZCode PermissionRequest hook — 把询问转发到 Touch Bar 助手。
#
# stdin:  ZCode 事件 JSON（单行）
# stdout: 决策 JSON（hookSpecificOutput…），或为空 = 降级到 ZCode 原生询问界面
#
# 退出码始终为 0；任何异常都不应阻断 ZCode 的权限流程。
set -u

STATE_DIR="${ZCODE_TOUCHBAR_STATE_DIR:-$HOME/Library/Application Support/zcode-touchbar}"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT_SECONDS="${ZCODE_TOUCHBAR_WAIT:-60}"

mkdir -p -m 700 "$STATE_DIR" 2>/dev/null || true

# exec 让 osascript 直接继承 stdin，避免 shell 缓存大 payload
exec osascript -l JavaScript "$HOOK_DIR/parse.jxa" "$STATE_DIR" "$WAIT_SECONDS"
