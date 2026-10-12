#!/usr/bin/env bash
# Godot --export-release 的 segfault 自动重试封装
#
# 为什么要有这个脚本：
#   Godot 4.3 在清空 web/build 触发全量 reimport 后偶发段错误（exit 139）。
#   历史 3 次全部"重试一次即成功"，但任一次崩溃都会卡住整个发版流程。
#   2026-10-12 实测两种失败形态：
#     冷缓存全量 reimport 阶段崩溃 → exit 139、无明文错误（重试可解）
#     缓存热时的真实错误（如预设名不存在）→ exit 1 + 明文 "Invalid export
#     preset name"，重试无意义
#   所以按退出码分流：139 重试，其它直接亮日志退出。
#
# 用法： bash scripts/export_with_retry.sh <预设名> [日志路径] [额外 godot 参数...]
#   例： bash scripts/export_with_retry.sh "Web" /tmp/exp.log
#       bash scripts/export_with_retry.sh "Linux" /tmp/exp.log "$OUT/game.x86_64"
# 退出： 0=导出成功；139=重试耗尽仍段错误；其它=godot 真实错误码（不重试，直接亮日志）
set -uo pipefail

GODOT="${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="${1:?用法: bash scripts/export_with_retry.sh <预设名> [日志] [额外 godot 参数]}"
LOG="${2:-/tmp/godot_export.log}"
shift 2 2>/dev/null || shift $#

MAX_TRIES="${MAX_TRIES:-3}"
for attempt in $(seq 1 "$MAX_TRIES"); do
  "$GODOT" --headless --path "$PROJ" --export-release "$PRESET" "$@" >"$LOG" 2>&1
  code=$?
  if [ $code -eq 0 ]; then
    exit 0
  fi
  if [ $code -ne 139 ]; then
    # 非段错误的真实错误（脚本语法错/资源丢失等）——重试无意义，直接亮日志
    echo "❌ 导出 $PRESET 失败（exit $code），日志尾部："
    grep -iv "_get_font_data\|text_server_adv" "$LOG" | tail -15
    exit $code
  fi
  echo "  ! 第 $attempt/$MAX_TRIES 次导出 $PRESET 段错误（exit 139，Godot 已知偶发），重试..."
done

echo "❌ 连续 $MAX_TRIES 次导出 $PRESET 段错误（exit 139），已不是偶发。日志：$LOG"
grep -iv "_get_font_data\|text_server_adv" "$LOG" | tail -15
exit 139
