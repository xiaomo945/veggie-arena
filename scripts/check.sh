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
  if grep -qE '\b(Art|Data|Events|GameState)\.' "$f" 2>/dev/null; then
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
echo "=== 2. 单元测试（headless） ==="
if [ -f tests/run_tests.gd ]; then
  "$GODOT" --headless --path . --script res://tests/run_tests.gd
  tfail=$?
else
  echo "  ⚠ 还没有 tests/run_tests.gd（阶段 0.8 待完成）"
  tfail=0
fi

echo ""
echo "=== 3. 行数检查（单文件 > 300 行必须拆） ==="
while IFS= read -r f; do
  c=$(wc -l < "$f")
  if [ "$c" -gt 300 ]; then echo "  ⚠ 超过 300 行: $f ($c 行)"; fi
done < <(find . -name "*.gd" -not -path "./.godot/*")
echo "  检查完成"

echo ""
if [ "$fail" -eq 0 ] && [ "$tfail" -eq 0 ]; then
  echo "=== ✅ 全部通过 ==="
else
  echo "=== ❌ 有失败项 ==="
  exit 1
fi
