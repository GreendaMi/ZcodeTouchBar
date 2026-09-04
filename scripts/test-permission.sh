#!/bin/bash
# 模拟一次工具权限确认事件，走完整 hook 流程。
# Touch Bar 应点亮显示「✓ 允许 / ✕ 拒绝」，点选后此脚本打印发给 ZCode 的决策 JSON。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> 向 Touch Bar 发送测试权限确认（等待点选，最长 60s）…"
{
  echo '{"hook_event_name":"PermissionRequest","tool_name":"Bash","reason":"Tool Bash requires approval","riskLevel":"medium","tool_input":{"command":"rm -rf /tmp/demo-build"}}'
} | bash "$ROOT/plugin/hooks/ask.sh"

echo "==> 上面若无输出且 Touch Bar 无反应：助手未运行（bash scripts/install.sh），或超时降级。"
