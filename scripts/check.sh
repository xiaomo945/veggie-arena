#!/usr/bin/env bash
# 一键自检：GDScript 语法检查 + headless 跑全部测试
# 用法：bash scripts/check.sh
set -u
GODOT="${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/godot" || exit 1

echo "=== 1. GDScript 语法检查 ==="
fail=0
n=0
while IFS= read -r f; do
  n=$((n+1))
  if ! "$GODOT" --headless --check-only --script "$f" >/dev/null 2>&1; then
    echo "  语法错误: $f"
    "$GODOT" --headless --check-only --script "$f" 2>&1 | head -5
    fail=$((fail+1))
  fi
done < <(find . -name "*.gd" -not -path "./.godot/*")
echo "  检查了 $n 个 .gd 文件，语法错误 $fail 个"

echo ""
echo "=== 2. 单元测试（headless） ==="
if [ -f tests/run_tests.gd ]; then
  "$GODOT" --headless --script tests/run_tests.gd
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
