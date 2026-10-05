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
echo "=== 2.5 发行包纯净度（把不该进包的东西拦在上传前）==="
# ⚠️ 千万别改成 grep pck 二进制里的路径字符串 —— 那会误报。
# 真踩过：pck 里确实能扫到 "res://art/store/og_image.png" 和 "res://tests/xxx.gd"，
# 但用 Godot 自己 load_resource_pack + 列目录一看，包里 372 个文件、零泄漏。
# 那些字符串来自 .import 重映射元数据（记录源文件路径），不是打包的资源本身。
# 所以这里用 Godot 权威列目录，别自己解 pck 二进制（Godot 4.3 的目录项布局
# 试了两版都解出垃圾 size）。
PCK="$BUILD/index.pck"
if [ -f "$PCK" ]; then
  leak=$("$GODOT" --headless --path "$PROJ" --script res://scripts/pck_ls.gd -- \
    "$PCK" res://tests/ res://scripts/ res://art/store/ res://art/raw/ 2>/dev/null \
    | grep -E "^res://" | sed 's/^/     /')
  if [ -n "$leak" ]; then
    echo "  ❌ 发行包混进了不该有的文件："
    echo "$leak"
    echo "     若是带 class_name 的 .gd：全局脚本类表不受 export_presets 的"
    echo "     exclude_filter 约束，去掉 class_name 改用 preload 引用即可。"
    exit 1
  fi
  echo "  ✅ 发行包干净（无 tests/ scripts/ art/store/ art/raw/ 泄漏）"
else
  echo "  ⚠ 没有 $PCK，跳过"
fi

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
