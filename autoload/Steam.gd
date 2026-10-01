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
# ⚠️ 写入的是存档里的【累计】统计，不是本局值：Steam 的 setStatInt 不会自动累加，
#    若直接写本局 wave/kills/gold 会每局覆盖成单局值，导致统计与 unlocks.json 进度错位、
#    依赖累计值的成就/统计永不触发。SaveMgr.record_run 已在 Game._finish_run 里先跑过，
#    这里读到的 data 已经是本局累加后的最新值。
#    统计 id 刻意与 Save.gd FIELDS / unlocks.json 的 progression type 对齐（best_wave 而非 max_wave）。
func record_run(wave: int, kills: int, gold: int, won: bool) -> void:
	if not _ok:
		return
	var s = Engine.get_singleton("Steam")
	var save_data: Dictionary = SaveMgr.data
	if s.has_method("setStatInt"):
		s.setStatInt("best_wave", int(save_data.get("best_wave", 0)))
		s.setStatInt("total_kills", int(save_data.get("total_kills", 0)))
		s.setStatInt("total_gold", int(save_data.get("total_gold", 0)))
		s.setStatInt("wins", int(save_data.get("wins", 0)))
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
