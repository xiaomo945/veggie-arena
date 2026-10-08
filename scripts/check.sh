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
  # 名单要与 project.godot 的 autoload 完全一致：漏一个就会把"用了 autoload 的文件"
  # 当成语法错误误报（HudLayout / ScreenMode 曾被漏掉，误报过 2 个文件）。
  if grep -qE '\b(Art|Data|Events|GameState|Settings|Steam|SaveMgr|Sfx|Bgm|Gamepad|I18n|HudLayout|ScreenMode|Perf)\.' "$f" 2>/dev/null; then
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
#
# 只扫"会真的渲染到屏幕上"的中文：
#   - 不扫 .md：文档里的中文永远不会进游戏画面，否则每写一行注释/文档就要重出字体；
#   - .gd 先剥掉注释再扫（复用架构守卫的 strip_code），注释里的汉字同样不上屏。
if [ -f fonts/NotoSansSC-Subset.otf ]; then
  PY=$(command -v python3.11 || command -v python3)
  miss=$("$PY" - "$ROOT" <<'PY'
import os, re, sys
from fontTools.ttLib import TTFont
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, 'scripts'))
from arch_guard import strip_code
CJK = re.compile(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3000-\u303F\uFF00-\uFFEF]')
SCAN = ('.gd', '.json', '.tscn', '.tres', '.cfg', '.csv', '.txt')
used = set()
for base, _, files in os.walk(root):
    if '/.git' in base or '/.godot' in base:
        continue
    for f in files:
        if not f.endswith(SCAN):
            continue
        text = open(os.path.join(base, f), encoding='utf-8', errors='ignore').read()
        if f.endswith('.gd'):
            text = strip_code(text)
        for ch in text:
            if CJK.match(ch):
                used.add(ch)
cm = TTFont(os.path.join(root, 'fonts/NotoSansSC-Subset.otf')).getBestCmap()
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
echo "=== 1.65 项目配置守卫（硬失败：防 project.godot 静默失效）==="
# 两类事故都真实发生过：
#   ① 中文注释被 Godot 的 ConfigFile 并进下一个键名 → 设置等于没写（HiDPI 那条
#      就一直是 true，手机按 DPR 2~3 渲染，填充率爆掉，是"怪多就卡"的真凶之一）；
#   ② 键名拼错 → 静默回落到引擎默认。
# 两者都【不报错、不崩溃】，只在实际跑起来时表现为性能差/行为怪，极难查。
if [ -f scripts/cfg_guard.py ]; then
  PYCFG=$(command -v python3.11 || command -v python3)
  if ! "$PYCFG" scripts/cfg_guard.py; then
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 scripts/cfg_guard.py，跳过"
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
echo "=== 2.4 UI / 输入层守卫（--scene 模式，autoload 真实注册）==="
# 为什么单开一段：单元测试跑在 --script 模式，那里【不注册 autoload】，
# UI 层根本没法实例化；而最近 8 次提交修的 bug（触屏点不动 / 卡片偏移 /
# START 点不到 / 详情页全屏拦截 / 跳过选武器页 / 进游戏没怪）100% 出在这一层，
# 而那一层当时【零测试】—— 所以 bug 流止不住。这一段把那一类 bug 变成机器判的断言。
#
# 已做变异测试（证明不是伪测试）：注入"跳过选武器页""关掉触屏模拟"
# "武器详情页全屏拦截"三个历史 bug，三个都被抓住（退出码 1）。
# 以后每修一个 UI/输入层 bug，都要在这里补一条断言，否则它还会回来。
if [ -f tests/ui/UITest.tscn ]; then
  uout=$(timeout 120 "$GODOT" --headless --path . --scene res://tests/ui/UITest.tscn 2>&1)
  uexit=$?
  echo "$uout" | grep -E "^  (OK|FAIL):"
  if [ "$uexit" -ne 0 ]; then
    echo "  ❌ UI/输入层守卫失败（见上面 FAIL 行）"
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 tests/ui/UITest.tscn，跳过"
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
echo "=== 2.6 每波强度规划（硬失败：每一波都必须落在带内）==="
# 用户诉求："每一波都要有一个规划，使这个角色的强度不能超标太多，也不能太弱"。
# 判的是 scripts/power_band.py 里那五条线（ratio / 成长 / 金币 / 等级 / 清场率），
# 数据由 scripts/power_probe.gd 直调真实 core/ 代码产出。改任何经济或血量数值
# 都会在这里被拦住 —— 这里是"难度曲线"唯一的自动闸门。
if [ -f scripts/power_band.py ]; then
  PY4=$(command -v python3.11 || command -v python3)
  if ! "$PY4" scripts/power_band.py --waves 20; then
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 scripts/power_band.py，跳过"
fi

echo ""
echo "=== 2.7 多用户画像角色评审（硬失败：6 个画像都要满意）==="
# 用户诉求："用户画像就是轻度、中度、重度用户，还有男生女生的喜好这样来评分儿…
#   他的名字、武器、玩法、爽感、特效美术，每一个环节都要模仿用户画像打分儿…
#   都满意了，或者打到一个比较高的分儿，这个角色才能做。"
# 两个闸门：① 每个画像的加权分 ≥ pass；② 任何一项 ≤ hard_floor 就是硬伤。
# 缺分（新角色忘了打分）同样算失败 —— 不允许悄悄跳过。
if [ -f scripts/char_review.py ]; then
  PY5=$(command -v python3.11 || command -v python3)
  if ! "$PY5" scripts/char_review.py; then
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 scripts/char_review.py，跳过"
fi

echo ""
echo "=== 2.8 帧率回归闸门（D2：CPU 每帧热点，确定性，可进 CI）==="
# 真机 GPU 帧率沙箱量不出（llvmpipe 软渲染无代表性，perf_probe.gd 仅作手动诊断），
# 但"怪一多就卡"的 CPU 侧每帧热点（分离 O(n²)/自动瞄准/敌人数组收集）可隔离、
# 可复现、可断言。这些函数退化成更糟复杂度时这里立刻红 —— 不依赖软渲染机时。
# GPU draw call 一侧由 tests/test_perf_guard.gd（max_alive 档位 38/32/26/20）守。
if [ -f scripts/perf_regression.py ]; then
  PY6=$(command -v python3.11 || command -v python3)
  if ! "$PY6" scripts/perf_regression.py; then
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 scripts/perf_regression.py，跳过"
fi

echo ""
echo "=== 2.9 击杀特效尖峰闸门（B 类卡顿：清场那一帧的瞬时开销）==="
# 与 2.8 互补：2.8 守【稳态】每帧热点，这里守【尖峰】。稳态均值看不见尖峰——
# 平均 60fps、清场那一帧 30ms，均值照样漂亮，玩家却实实在在觉得卡。
# "怪一多就卡"就是这一类：击杀特效的开销随击杀数线性增长。
if [ -f scripts/fx_band.py ]; then
  PY7=$(command -v python3.11 || command -v python3)
  if ! "$PY7" scripts/fx_band.py; then
    fail=$((fail+1))
  fi
else
  echo "  ⚠ 缺少 scripts/fx_band.py，跳过"
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
