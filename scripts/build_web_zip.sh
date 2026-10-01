#!/usr/bin/env bash
# 打包 itch.io 用的 HTML5 zip
#
# 为什么要有这个脚本：
#   1) 导出前必须从零重建，否则 web/build 里会残留上一次的无用资源
#   2) 必须校验 pck 里没有混进"非游戏资源"（商店宣传图/测试脚本/工具脚本）
#      —— 这类东西白白占首包体积，玩家下载它们是纯浪费
#   3) itch.io 要求 index.html 必须在 zip 根目录
#
# 用法： bash scripts/build_web_zip.sh
# 产物： /workspace/TURNIP_TROUBLE_web.zip
set -uo pipefail

GODOT="${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$PROJ/web/build"
ZIP="/workspace/TURNIP_TROUBLE_web.zip"
fail=0

echo "=== 1. 从零导出 Web release ==="
rm -rf "$BUILD"
mkdir -p "$BUILD"
"$GODOT" --headless --path "$PROJ" --export-release "Web" >/tmp/exp.log 2>&1
exp=$?
if [ $exp -ne 0 ]; then
  echo "❌ 导出失败（exit $exp），日志尾部："
  grep -iv "_get_font_data\|text_server_adv" /tmp/exp.log | tail -15
  exit 1
fi
[ -f "$BUILD/index.html" ] || { echo "❌ 导出后没有 index.html"; exit 1; }
[ -f "$BUILD/index.wasm" ] || { echo "❌ 导出后没有 index.wasm"; exit 1; }
echo "  ✅ 导出完成"

echo
echo "=== 2. 校验 pck 里没有非游戏资源 ==="
python3 - "$BUILD/index.pck" <<'PY'
import struct, sys
BAD = ("library_hero", "og_image", "capsule_", "flat_vector",
       "/tests/", "/scripts/", "/tools/", "/web/")
f = open(sys.argv[1], "rb")
cnt = struct.unpack("<I", f.read(100)[96:100])[0]
rows = []
for _ in range(cnt):
    ln, = struct.unpack("<I", f.read(4))
    p = f.read(ln).rstrip(b"\0").decode("utf8", "replace")
    f.read((4 - (ln % 4)) % 4); f.read(16); f.read(16); f.read(4)
    rows.append(p)
bad = [r for r in rows if any(k in r for k in BAD)]
if bad:
    print("  ❌ pck 里混进了非游戏资源 %d 项：" % len(bad))
    for b in bad[:8]:
        print("     ", b)
    sys.exit(1)
print("  ✅ pck 干净：%d 个文件，无商店图/测试/工具残留" % len(rows))
PY
[ $? -ne 0 ] && fail=1

echo
echo "=== 3. 体积与压缩后预估 ==="
python3 - "$BUILD" <<'PY'
import os, sys, brotli
d = sys.argv[1]
tot_r = tot_b = 0
for n in sorted(os.listdir(d)):
    p = os.path.join(d, n)
    if not os.path.isfile(p):
        continue
    r = os.path.getsize(p)
    b = len(brotli.compress(open(p, "rb").read(), quality=11))
    tot_r += r; tot_b += b
    print("  %-24s %7.2f MB → brotli %6.2f MB" % (n, r / 1048576, b / 1048576))
print("  %-24s %7.2f MB → brotli %6.2f MB" % ("【首屏合计】", tot_r / 1048576, tot_b / 1048576))
print()
print("  4G(10Mbps) 预估首屏：无压缩 %.0fs / 有 brotli %.0fs" % (tot_r * 8 / 10e6, tot_b * 8 / 10e6))
if tot_b > 20 * 1048576:
    print("  ⚠️  brotli 后仍 > 20MB，首屏偏重，需要继续瘦身")
PY

echo
echo "=== 4. 打 zip（index.html 必须在根目录）==="
rm -f "$ZIP"
(cd "$BUILD" && zip -q -9 -r "$ZIP" .)
echo "  ✅ $ZIP"
ls -la "$ZIP" | awk '{printf "     %.1f MB\n", $5/1048576}'

echo
echo "=== 5. zip 根目录自检 ==="
python3 - "$ZIP" <<'PY'
import zipfile, sys
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
roots = {n.split("/")[0] for n in names}
need = ["index.html", "index.wasm", "index.pck", "index.js"]
missing = [n for n in need if n not in roots]
print("  根目录文件:", ", ".join(sorted(roots)))
if missing:
    print("  ❌ 缺少:", missing)
    sys.exit(1)
print("  ✅ index.html 在根目录，itch.io 可直接识别")
PY
[ $? -ne 0 ] && fail=1

echo
if [ $fail -eq 0 ]; then
  echo "=== ✅ 打包完成 → $ZIP ==="
  echo "  上传到 https://itch.io/game/new ，Kind of project 选 HTML，"
  echo "  勾选 'This file will be played in the browser'，上传这个 zip 即可。"
else
  echo "=== ❌ 打包有上述问题，先修再传 ==="
fi
exit $fail
