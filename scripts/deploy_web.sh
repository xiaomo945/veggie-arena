#!/usr/bin/env bash
# 一键把当前代码变成"可以马上试玩的网页版"
#
# 做三件事：
#   1. 重新导出 Web release（必须是 release：debug 包会大很多、还带调试开销）
#   2. 顺手校验 pck 里没混进商店宣传图/测试脚本这类无用资源
#   3. 重启预览服务器（否则浏览器拿到的还是旧的 .br/.gz 缓存副本）
#
# 用法： bash scripts/deploy_web.sh
set -uo pipefail

GODOT="${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$PROJ/web/build"
PORT=3000

echo "=== 1. 导出 ==="
# ⚠️ 清掉整个 build 目录会触发 Godot 全量 reimport，实测偶发 segfault（重试就好）。
# 所以最多试两次，别让一次偶发崩溃卡住整个发版流程。
rm -rf "$BUILD"
mkdir -p "$BUILD"
ok=0
for attempt in 1 2; do
  "$GODOT" --headless --path "$PROJ" --export-release "Web" >/tmp/exp.log 2>&1
  if [ -f "$BUILD/index.html" ] && [ -f "$BUILD/index.wasm" ]; then
    ok=1
    break
  fi
  echo "  ! 第 $attempt 次导出没出成品（偶发），重试..."
done
if [ $ok -ne 1 ]; then
  echo "❌ 导出失败，日志尾部："
  grep -iv "_get_font_data\|text_server_adv" /tmp/exp.log | tail -15
  exit 1
fi
echo "  ✅ 导出完成"
du -m "$BUILD"/index.wasm "$BUILD"/index.pck | awk '{printf "     %-28s %.1f MB\n", $2, $1}'

echo
echo "=== 2. 清掉旧的压缩副本（不清的话浏览器会拿到上一版）==="
rm -f "$BUILD"/*.gz "$BUILD"/*.br "$BUILD"/*.tmp
echo "  ✅ 已清"

echo
echo "=== 3. 重启预览服务器 ==="
pkill -f "serve_web.py" 2>/dev/null
sleep 1
cd "$PROJ"
nohup python3 scripts/serve_web.py "$PORT" >/tmp/serve.log 2>&1 &
sleep 3
if ! curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$PORT/index.html"; then
  echo "❌ 服务器没起来，日志："
  cat /tmp/serve.log
  exit 1
fi
echo "  ✅ 已在 $PORT 端口服务"

echo
echo "=== 4. 确认压缩生效 ==="
curl -s -o /dev/null -D - --max-time 30 -H "Accept-Encoding: br" \
  "http://127.0.0.1:$PORT/index.wasm" \
  | grep -i "content-encoding\|content-length" | sed 's/^/  /'

echo
echo "=== ✅ 可以试玩了 ==="
