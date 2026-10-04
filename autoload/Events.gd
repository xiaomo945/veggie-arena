extends Node

# 信号总线：模块之间只通过这里通信，不直接互相引用。
# 规则：core/ 层不许 emit 信号（保持纯函数）；
#       entities/ 与 ui/ 可以 emit，也可以 connect。

# ---- 战斗 ----
signal player_hp_changed(hp: int, max_hp: int)
signal player_died()
signal enemy_spawned(enemy: Node)
signal enemy_killed(type: String, pos: Vector2)
# 自爆怪贴脸爆炸（纯表现层：画一圈冲击环 + 迸溅），订阅方见 FxLayer
signal enemy_exploded(pos: Vector2, radius: float)
signal damage_dealt(amount: int, pos: Vector2, critical: bool)
# 闪避成功（被动道具 dodge）：整次伤害被免掉，用于飘"MISS"字/音效
signal player_dodged(pos: Vector2)

# ---- 波次 ----
signal wave_started(wave: int)
# 波次撑满（波末结算已入袋、即将开补给站）。pos=玩家位置，供过关庆祝特效定位。
signal wave_ended(wave: int, pos: Vector2)
signal wave_progress(elapsed: float, length: float)
signal boss_wave(wave: int)
# 终局 Boss 波：比 boss_wave 更有分量（HUD 横幅更大、BGM 也切 boss 曲）。
# 与 boss_wave 互斥发出 —— 终局波只发这一个，避免两条横幅互相覆盖。
signal final_boss_wave(wave: int)
# 通关后选择"继续无尽"：由胜利页发出、Game 接管推进到 total+1 波
signal endless_continue_requested()
# 已进入无尽段（波次越过了最终波）
signal endless_started(wave: int)

# ---- 锅气 Wok Heat ----
signal wok_heat_changed(value: float, tier: int)
signal wok_tier_changed(tier: int)
signal wok_ready_changed(ready: bool)
signal wok_charges_changed(charges: int)
signal wok_tossed(pos: Vector2)
signal shield_changed(value: int)
# HUD 颠勺按钮 / Joystick 避让区点按发出，由 Game 真正执行
signal wok_toss_requested()

# ---- 主动技能（锅气之外的手动释放技能：冰镇 / 毒雾 …）----
# HUD 技能按钮按下发出（带技能 id），由 Game 真正施放；与锅气同级的"右手技能"。
signal skill_requested(id: String)
# SkillSystem → HUD：某技能冷却进度(0..1)与是否可用，画按钮冷却扇形
signal skill_cooldown_changed(id: String, ratio: float, ready: bool)
# 施放成功的特效信号（纯表现层 FxSkill 订阅）；pos/radius 是玩家世界坐标与影响半径
signal skill_cast(id: String, pos: Vector2, radius: float)

# ---- 调试（仅调试模式，见 core/DebugMode：正式版按钮都不创建，此信号没人发）----
# HUD 调试面板"跳到第 N 波"发出，由 WaveDirector 真正执行（清场后直接开那一波）
signal debug_jump_wave(wave: int)

# ---- 经济 ----
signal gold_changed(gold: int)
signal pickup_spawned(pos: Vector2, value: int)
# 玩家吃到一枚金币（音效/特效订阅；加钱由 Game 直接调 GameState.add_gold）
signal pickup_collected(pos: Vector2, value: int)

# ---- 存档 / 解锁 ----
# 一局结束后，新达成解锁的武器逐个发出（HUD 弹提示用）
signal unlocked(key: String)

# ---- 角色 ----
# 标题页选人时发出；Player/GameState 各自响应（换贴图 / 重算上限）
signal character_changed(key: String)

# ---- 装备 ----
signal weapons_changed(weapons: Array)
signal weapon_merged(key: String, level: int)

# 金币拾取范围预览：买完"拾取范围"类强化后由 UI 层 emit（core 不 emit），
# FxLayer 订阅并画一圈从玩家扩散到半径的金色环，让看不见的拾取范围变化一眼可见。
signal player_range_preview(radius: float)

# ---- 战斗发射 ----
# Player 只发信号说"我要往这个方向打一发"，不认识子弹、也不认识敌人列表
# key = 武器 key（pistol/smg/rocket…），供特效层按武器做专属火光
signal weapon_fired(pos: Vector2, dir: Vector2, stats: Dictionary, color: Color, key: String)

# ---- 近战挥砍 ----
# PlayerWeapons 在冷却到点、瞄准最近敌人后发出；真正结算（伤害漏斗/击退/视觉）
# 由 EnemySystem 完成。dir=挥砍朝向，reach=弧半径，half_arc=半角（弧度），
# dmg=已含暴击与全局加成的单跳伤害，knockback=击退脉冲（0 表示不击退）。
signal melee_swung(origin: Vector2, dir: Vector2, reach: float, half_arc: float,
	dmg: float, crit: bool, knockback: float, color: Color, key: String, level: int)
# 纯视觉：Fx 层画一个短命扇形 + 地面裂痕。和伤害结算解耦（删掉 Fx 游戏照样能打）。
# key/level 用于按武器种类与等级做不同的特效（如菜刀砍地裂痕随等级变长）。
signal melee_visual(origin: Vector2, dir: Vector2, reach: float, half_arc: float, color: Color, key: String, level: int)

# ---- 操作输入 ----
# 摇杆只发信号，不认识 Player；Player 只收信号，不认识摇杆。
signal stick_dir_changed(dir: Vector2)
signal stick_released()
# 冲刺闪避：HUD 按钮 / 摇杆避让区点按发出，由 Player 执行
signal dash_requested()
# Player → HUD：冷却进度(0..1)与是否可用，用于画按钮冷却扇形
signal dash_state_changed(ratio: float, ready: bool)
# 冲刺起步的视觉反馈（残影/尘土），纯表现层订阅
signal dash_started(pos: Vector2, dir: Vector2)

# 快进（2 倍速）开关：HUD 快进按钮按下发出，由 Game 真正改战斗倍率
signal fast_forward_toggled(on: bool)

# ---- 流程 ----
signal run_started()
signal run_ended(wave: int, kills: int)
# 撑过最后一波通关时发（胜利页监听），与 player_died（阵亡）互斥
signal run_won()
signal shop_opened()
signal shop_closed()
# 标题页"开始"/死亡页"再来一局"都发这个，由 Main 统一接管开跑/重开
signal run_requested()
# 暂停：HUD 暂停键发出 → Game 真正暂停；PauseScreen 监听 run_paused 显隐自己
signal pause_requested()
signal resume_requested()
signal run_paused(paused: bool)
# 暂停菜单"退出到标题" → Game 复位本局 + TitleScreen 重新显示
signal quit_to_title_requested()
