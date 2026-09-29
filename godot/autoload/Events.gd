extends Node

# 信号总线：模块之间只通过这里通信，不直接互相引用。
# 规则：core/ 层不许 emit 信号（保持纯函数）；
#       entities/ 与 ui/ 可以 emit，也可以 connect。

# ---- 战斗 ----
signal player_hp_changed(hp: int, max_hp: int)
signal player_died()
signal enemy_spawned(enemy: Node)
signal enemy_killed(type: String, pos: Vector2)
signal damage_dealt(amount: int, pos: Vector2, critical: bool)

# ---- 波次 ----
signal wave_started(wave: int)
signal wave_ended(wave: int)
signal wave_progress(elapsed: float, length: float)

# ---- 经济 ----
signal gold_changed(gold: int)
signal pickup_spawned(pos: Vector2, value: int)

# ---- 装备 ----
signal weapons_changed(weapons: Array)
signal weapon_merged(key: String, level: int)

# ---- 战斗发射 ----
# Player 只发信号说"我要往这个方向打一发"，不认识子弹、也不认识敌人列表
signal weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, color: Color)

# ---- 操作输入 ----
# 摇杆只发信号，不认识 Player；Player 只收信号，不认识摇杆。
signal stick_dir_changed(dir: Vector2)
signal stick_released()

# ---- 流程 ----
signal run_started()
signal run_ended(wave: int, kills: int)
signal shop_opened()
signal shop_closed()
