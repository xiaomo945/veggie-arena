extends Node

const Economy := preload("res://core/Economy.gd")

# 波次流程：撒怪 / 开波 / 波末结算 / 商店关闭后进入下一波。
# 不持有战斗状态——统一通过注入的 world / enemy_system / game 访问，
# 避免与 Game 重复维护一份状态，也满足架构守卫 R3（不跨模块读私有字段）。
# 注意：所有对外调用都用公开方法/公开字段（无 X._yyy），否则会被 R3 拦下。

var game: Node = null            # Game 协调器（用于暂停控制）
var world = null                 # BattleWorld 共享状态
var enemy_system = null          # 刷怪/敌人子系统

func setup(g: Node, w, es) -> void:
	game = g
	world = w
	enemy_system = es
	# 调试面板"跳到第 N 波"（core/DebugMode 决定按钮存不存在，正式版没人发这个信号）
	Events.debug_jump_wave.connect(jump_to_wave)

# 每波开局先撒一批怪（数量 = spawn_burst + 波号，不超 max_alive）
func spawn_wave_burst() -> void:
	var cfg := Data.spawn_cfg()
	var n := int(cfg.get("spawn_burst", 14)) + GameState.wave
	# 走 Perf.alive_cap：开局这一批也得守当前画质档的上限（以前只读 spawn 配置，
	# 结果"档位已降到保底，开局照旧撒满 38 只"）
	var cap := Perf.alive_cap(int(cfg.get("max_alive", 88)))
	for _i in n:
		if world.alive_enemy_count() >= cap:
			break
		enemy_system.spawn_one()

# 开一波：Boss 波开局刷首领并通知 HUD 弹横幅（终局波发专属信号），再撒一批怪
func begin_wave() -> void:
	if enemy_system.boss_wave():
		if enemy_system.final_wave():
			Events.final_boss_wave.emit(GameState.wave)
		else:
			Events.boss_wave.emit(GameState.wave)
		enemy_system.spawn_boss()
	spawn_wave_burst()

# 波末收尾：地上钱入袋(按损耗扣减) + 波次奖励 + 回血 + 过关庆祝 + 开补给站/胜利
func end_wave() -> void:
	# 波末清场：地上没捡的钱自动入袋，但按 wave_end_loss 扣减（fullauto=0 损耗）
	if world.pickups != null:
		var swept: int = world.pickups.collect_all(world.player.global_position)
		if swept > 0:
			world.gold_picked += swept
			var kept: int = int(float(swept) * (1.0 - GameState.gold_sweep_loss()))
			if kept > 0:
				GameState.add_gold(kept)
	GameState.add_gold(Economy.wave_bonus(GameState.wave, Data.wave_cfg()))
	GameState.heal_percent(float(Data.wave_cfg().get("heal_percent", 0.12)))
	# 波末回血（wave_heal）：固定值，与上面的百分比回血叠加，是"续航流"的核心
	var wh := int(round(GameState.stat_value("wave_heal")))
	if wh > 0:
		GameState.heal(wh)
	# 过关庆祝（卡通彩纸）：在开补给站之前发，Fx 层画在商店之上所以看得见
	Events.wave_ended.emit(GameState.wave, world.player.global_position)
	# 最后一波结束 = 通关：停跑并弹胜利页，不再开补给站
	if GameState.is_last_wave():
		GameState.running = false
		Events.run_won.emit()
		return
	game.set_paused(true)
	Events.shop_opened.emit()

# 商店关闭：恢复战斗并推进到下一波（复用开波流程）
func on_shop_closed() -> void:
	game.set_paused(false)
	GameState.next_wave()
	begin_wave()

# 调试：直接跳到第 n 波（清场后按那一波开打），让你不必为看第 15 波先打 14 波。
# 只被 Events.debug_jump_wave 触发；按钮本体只在调试模式创建（core/DebugMode）。
func jump_to_wave(n: int) -> void:
	var total := int(Data.wave_cfg().get("total", 20))
	GameState.wave = clampi(n, 1, maxi(total, 1))
	GameState.elapsed_in_wave = 0.0
	for e in world.enemies:
		if e.alive:
			e.recycle()
	for b in world.bullets:
		if b.active:
			b.recycle()
	if world.pickups != null:
		world.pickups.clear()
	world.reset_run()
	begin_wave()
	Events.wave_started.emit(GameState.wave)
