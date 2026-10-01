#!/usr/bin/env bash
# 一键自检：GDScript 语法检查 + headless 跑全部测试
# 用法：bash scripts/check.sh
set -u
GODOT="${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

echo "=== 1. GDScript 语法检查 ==="
# 注意：--script 模式不会注册 autoload，引用 Data/Events/GameState 的文件
# 会误报 "Identifier not found"。这类文件交给第 2 步的"主场景启动"验证，
# 那里 autoload 是真实注册的，能抓到真正的错误。
fail=0
n=0
skip=0
while IFS= read -r f; do
  if grep -qE '\b(Art|Data|Events|GameState|Settings|Steam|SaveMgr|Sfx|Bgm|Gamepad)\.' "$f" 2>/dev/null; then
    skip=$((skip+1))
    continue
  fi
  n=$((n+1))
  if ! "$GODOT" --headless --check-only --script "$f" >/dev/null 2>&1; then
    echo "  语法错误: $f"
    "$GODOT" --headless --check-only --script "$f" 2>&1 | head -5
    fail=$((fail+1))
  fi
done < <(find . -name "*.gd" -not -path "./.godot/*")
echo "  逐文件检查 $n 个，语法错误 $fail 个；跳过 $skip 个（用 autoload，由第 2 步覆盖）"

echo ""
echo "=== 1.5 主场景启动验证（autoload 真实注册，清缓存强制重编译）==="
# ⚠️ 必须清 .godot/editor 缓存：否则 Godot 会用旧编译的 Game.gd 等脚本，
# 漏掉"类型推断失败"这类 Parse Error（v0.11 的 desired 变量就因此漏过）
rm -rf .godot/editor
boot_out=$("$GODOT" --headless --path . --quit-after 60 2>&1)
if echo "$boot_out" | grep -qiE "SCRIPT ERROR|Parse Error|Compile Error|Identifier not found"; then
  echo "  ❌ 主场景启动有错："
  echo "$boot_out" | grep -iE "SCRIPT ERROR|Parse Error|Compile Error|Identifier not found" | head -6
  fail=$((fail+1))
else
  echo "  ✅ 主场景启动无报错"
fi

echo ""
echo "=== 1.6 字体中文覆盖检查（漏字会变豆腐块）==="
# 校验 fonts/NotoSansSC-Subset.otf 是否覆盖项目当前用到的全部中文。
# 若以后加了新中文文案/武器名却没重出字体，这里会直接报错，避免"豆腐块"上线。
# 重出字体：python3 scripts/regen_font.py
if [ -f fonts/NotoSansSC-Subset.otf ]; then
  PY=$(command -v python3.11 || command -v python3)
  miss=$("$PY" - "$ROOT" <<'PY'
import os, re, sys
from fontTools.ttLib import TTFont
root = sys.argv[1]
CJK = re.compile(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3000-\u303F\uFF00-\uFFEF]')
used = set()
for base,_,files in os.walk(root):
    if '/.git' in base or '/.godot' in base:
        continue
    for f in files:
        if not f.endswith(('.gd','.json','.tres','.cfg','.md','.csv','.txt')):
            continue
        for ch in open(os.path.join(base,f), encoding='utf-8', errors='ignore').read():
            if CJK.match(ch):
                used.add(ch)
cm = TTFont(os.path.join(root,'fonts/NotoSansSC-Subset.otf')).getBestCmap()
print(''.join(sorted(c for c in used if ord(c) not in cm)))
PY
)
  if [ -n "$miss" ]; then
    echo "  ❌ 字体缺字（会显示成豆腐块）: $miss"
    echo "     修复：python3 scripts/regen_font.py  然后重新导出"
    fail=$((fail+1))
  else
    echo "  ✅ 字体覆盖全部中文（无豆腐块风险）"
  fi
else
  echo "  ⚠ 未找到 fonts/NotoSansSC-Subset.otf，跳过"
fi

echo ""
echo "=== 1.7 架构守卫（硬失败：存量只降不升，新增违规一律拦下）==="
# 规则见 scripts/arch_guard.py：R1 单文件行数 / R2 core 层纯度 / R3 跨模块读私有字段。
# 存量违规登记为基线（棘轮），所以今天就能硬生效，不必先重构完历史代码。
if [ -f scripts/arch_guard.py ]; then
  PY2=$(command -v python3.11 || command -v python3)
  if ! "$PY2" scripts/arch_guard.py; then
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 scripts/arch_guard.py，跳过"
fi

echo ""
echo "=== 2. 单元测试（headless） ==="
if [ -f tests/run_tests.gd ]; then
  "$GODOT" --headless --path . --script res://tests/run_tests.gd
  tfail=$?
else
  echo "  ⚠ 还没有 tests/run_tests.gd（阶段 0.8 待完成）"
  tfail=0
fi

echo ""
echo "=== 2.5 整局集成验证（重构安全网）==="
# 单元测试跑在 --script 模式，那里不注册 autoload，所以 Game/EnemySystem 这类
# 真正依赖 Data/Events/GameState 的模块没法被单测实例化。整条链路还通不通，
# 只能靠真跑一局来验证：刷怪 → 开火 → 命中 → 掉钱 → 波次推进（含商店结算）。
if [ -f scripts/run_sim.py ]; then
  PY3=$(command -v python3.11 || command -v python3)
  if ! "$PY3" scripts/run_sim.py 120; then
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 scripts/run_sim.py，跳过"
fi

echo ""
echo "=== 3. 说明 ==="
echo "  单文件 >300 行的检查已并入 1.7 架构守卫（硬失败，不再是只告警不拦人）"

echo ""
if [ "$fail" -eq 0 ] && [ "$tfail" -eq 0 ]; then
  echo "=== ✅ 全部通过 ==="
else
  echo "=== ❌ 有失败项 ==="
  exit 1
fi
