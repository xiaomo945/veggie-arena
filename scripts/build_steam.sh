#!/usr/bin/env bash
# 构建 Steam 桌面包（Linux / Windows）。
# 前置：
#   1) 已把 GodotSteam GDExtension 放进 addons/godotsteam/ 并在项目启用
#   2) steam_appid.txt 已填入你的真实 AppID
#   3) 已在 Godot 编辑器配置 Linux/X11 与 Windows 导出预设（沙箱无 GUI，需你本地做）
set -e
GODOT="${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-build/steam}"
mkdir -p "$OUT"
# GodotSteam 运行时从包根读取 AppID
cp steam_appid.txt "$OUT/steam_appid.txt"

export_one() {
  local preset="$1" out="$2"
  local log="/tmp/exp_steam_${preset}.log"
  # 走统一重试封装（scripts/export_with_retry.sh）：
  #   Godot 4.3 在全量 reimport 阶段偶发段错误（exit 139），重试即可成功；
  #   缓存热时"预设没配"是干净的 exit 1 + 明文错误，不重试。
  # 重试耗尽后看产物文件在不在，给调用方一个明确结论。
  if bash "$PROJ/scripts/export_with_retry.sh" "$preset" "$log" "$out" \
     && [ -f "$out" ]; then
    echo "  ✅ $preset → $out"
    return 0
  fi
  echo "  [跳过] $preset：预设未配置（或导出持续段错误），日志：$log"
  echo "         在 project.godot 配好对应导出预设后再跑本脚本"
  return 0
}

echo "== 导出 Linux =="
export_one "Linux" "$OUT/turnip_trouble.x86_64"
echo "== 导出 Windows =="
export_one "Windows" "$OUT/turnip_trouble.exe"
echo "完成：将 $OUT 打包上传 Steamworks depot。"
