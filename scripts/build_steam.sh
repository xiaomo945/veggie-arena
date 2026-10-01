#!/usr/bin/env bash
# 构建 Steam 桌面包（Linux / Windows）。
# 前置：
#   1) 已把 GodotSteam GDExtension 放进 addons/godotsteam/ 并在项目启用
#   2) steam_appid.txt 已填入你的真实 AppID
#   3) 已在 Godot 编辑器配置 Linux/X11 与 Windows 导出预设（沙箱无 GUI，需你本地做）
set -e
GODOT="${GODOT:-/opt/godot/Godot_v4.3-stable_linux.x86_64}"
OUT="${OUT:-build/steam}"
mkdir -p "$OUT"
# GodotSteam 运行时从包根读取 AppID
cp steam_appid.txt "$OUT/steam_appid.txt"
echo "== 导出 Linux =="
"$GODOT" --headless --export-release "Linux" "$OUT/turnip_trouble.x86_64" \
  || echo "[跳过] 需在 project.godot 配置 Linux/X11 导出预设"
echo "== 导出 Windows =="
"$GODOT" --headless --export-release "Windows" "$OUT/turnip_trouble.exe" \
  || echo "[跳过] 需在 project.godot 配置 Windows 导出预设"
echo "完成：将 $OUT 打包上传 Steamworks depot。"
