extends Node

# Steam 接入安全封装层。
# 通过 GodotSteam GDExtension 暴露的 "Steam" singleton 调用；若未挂载扩展
# （Web 构建 / 本地无 Steam 运行时），全部方法 no-op，绝不抛错——
# 这样游戏在任何环境都能正常跑，不会因为缺 Steam 而崩。
#
# ⚠️ 真上架前你还需要：
#   1) 下载 GodotSteam GDExtension 放进 addons/godotsteam/ 并在项目启用；
#   2) 在 steam_appid.txt 填入你的真实 AppID；
#   3) 本文件的方法名需对照你用的 GodotSteam 版本核对（has_method 已做保护，
#      即使名字不完全匹配也只是不生效，不会崩）。

var _ok := false

func _ready() -> void:
	if Engine.has_singleton("Steam"):
		var s = Engine.get_singleton("Steam")
		if s != null and s.has_method("steamInit"):
			var r = s.steamInit()
			_ok = (r is Dictionary) and bool(r.get("status", false))

func is_ready() -> bool:
	return _ok

# 一局结束：把成绩写进 Steam 统计，通关解锁首通成就
func record_run(wave: int, kills: int, gold: int, won: bool) -> void:
	if not _ok:
		return
	var s = Engine.get_singleton("Steam")
	if s.has_method("setStatInt"):
		s.setStatInt("max_wave", int(wave))
		s.setStatInt("total_kills", int(kills))
		s.setStatInt("total_gold", int(gold))
	if won and s.has_method("setAchievement"):
		s.setAchievement("first_clear")
	if s.has_method("storeStats"):
		s.storeStats()

func unlock(id: String) -> void:
	if not _ok:
		return
	var s = Engine.get_singleton("Steam")
	if s.has_method("setAchievement"):
		s.setAchievement(id)

func set_stat_int(id: String, value: int) -> void:
	if not _ok:
		return
	var s = Engine.get_singleton("Steam")
	if s.has_method("setStatInt"):
		s.setStatInt(id, value)
