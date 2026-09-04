#!/bin/bash
# 模拟一次 ZCode 的 AskUserQuestion 事件，走完整 hook 流程。
# Touch Bar 应点亮并显示 3 个选项，点选后此脚本打印发给 ZCode 的决策 JSON。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> 向 Touch Bar 发送测试提问（等待点选，最长 60s）…"
{
  echo '{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Touch Bar 测试：下面喝点什么？","header":"饮品","options":[{"label":"咖啡","description":"美式，加冰"},{"label":"茶","description":"龙井"},{"label":"白开水","description":"健康"}],"multiSelect":false}]}}'
} | bash "$ROOT/plugin/hooks/ask.sh"

echo "==> 上面若无输出且 Touch Bar 无反应：助手未运行（bash scripts/install.sh），或超时降级。"
