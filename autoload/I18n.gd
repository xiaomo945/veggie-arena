extends Node

# 多语言单例（方案 B：自定义字典映射，与 data/*.json 的 en/zh 内联字段完全一致）。
# 默认语言跟随系统：中文设备→中文（方便国内玩家与开发者测试），其余→英文（出海）。
# 首次启动后由 Settings 持久化语言偏好，_settings 菜单可随时手动切换 zh/en。
#   I18n.t(key)            -> UI 静态文案（zh/en 字典）
#   I18n.pick(d, ...)      -> 数据条目的名称字段（武器/角色/敌人/强化：en/zh）
#   I18n.tip(d)            -> 数据条目的描述字段（tip_en / tip）
#   I18n.stat_label(t)     -> 解锁进度里的统计名（kills/gold/wave/wins）
#   I18n.set_locale(code)  -> 切换语言，持久化到 Settings 并发 locale_changed
# locale_changed 供各界面订阅，语言切换时实时刷新自身文案。

signal locale_changed(locale: String)

var locale: String = "en"   # "en" / "zh"

# UI 静态文案：{ key: {en:.., zh:..} }。缺 key 时 t() 原样返回 key，便于发现遗漏。
const UI := {
  # ---- 设置菜单 ----
  "settings_title": {"en": "Settings", "zh": "设置"},
  "settings_music": {"en": "Music Volume", "zh": "音乐音量"},
  "settings_sfx": {"en": "SFX Volume", "zh": "音效音量"},
  "mute": {"en": "Mute", "zh": "静音"},
  "settings_move": {"en": "Move Speed", "zh": "移动速度"},
  "settings_quality": {"en": "Quality", "zh": "画质"},
  "quality_low": {"en": "Low", "zh": "低"},
  "set_blade": {"en": "Blade", "zh": "刀工"},
  "set_heavy": {"en": "Heavy", "zh": "重家伙"},
  "set_gun": {"en": "Firearms", "zh": "枪械"},
  "set_elemental": {"en": "Elemental", "zh": "元素"},
  "set_kitchen": {"en": "Kitchenware", "zh": "厨具"},
  "set_tier": {"en": "%s %d", "zh": "%s %d"},
  "set_tier_up": {"en": "%s ×%d!", "zh": "%s %d 件！"},
  "stat_melee": {"en": "Melee DMG", "zh": "近战伤害"},
  "stat_ranged": {"en": "Ranged DMG", "zh": "远程伤害"},
  "stat_elem": {"en": "Elemental DMG", "zh": "元素伤害"},
  "quality_mid": {"en": "Medium", "zh": "中"},
  "quality_high": {"en": "High", "zh": "高"},
  "settings_perf": {"en": "Auto quality", "zh": "自动画质"},
  "perf_level_0": {"en": "Full", "zh": "满配"},
  "perf_level_1": {"en": "Reduced", "zh": "轻度降级"},
  "perf_level_2": {"en": "Light", "zh": "中度降级"},
  "perf_level_3": {"en": "Minimal", "zh": "保底"},
  "settings_shake": {"en": "Screen Shake", "zh": "震屏"},
  "settings_particles": {"en": "Particles", "zh": "粒子"},
  "settings_fps": {"en": "Target FPS", "zh": "帧率目标"},
  "settings_show_fps": {"en": "FPS Counter", "zh": "显示帧率"},
  "settings_back": {"en": "Back", "zh": "返回"},
  "fps_default": {"en": "Default (Engine)", "zh": "默认 (引擎)"},
  "settings_language": {"en": "Language", "zh": "语言"},
  "lang_en": {"en": "English", "zh": "English"},
  "lang_zh": {"en": "中文", "zh": "中文"},
  "on": {"en": "ON", "zh": "开"},
  "off": {"en": "OFF", "zh": "关"},

  # ---- HUD ----
  "hud_gold": {"en": "GOLD %d", "zh": "金币 %d"},
  "hud_kills": {"en": "KILLS %d", "zh": "击杀 %d"},
  "hud_wave": {"en": "WAVE %d/%d", "zh": "波次 %d/%d"},
  "hud_final": {"en": " · FINAL", "zh": " · 终局"},
  "hud_boss_wave": {"en": "BOSS WAVE %d", "zh": "BOSS 波 %d"},
  "hud_final_wave": {"en": "FINAL WAVE %d", "zh": "最终波 %d"},
  "hud_wok_tier2": {"en": "BLAZING! DMG+SPD", "zh": "爆炒！伤害+攻速"},
  "hud_wok_tier1": {"en": "STIR-FRY! SPD UP", "zh": "翻炒！攻速提升"},
  "hud_toss": {"en": "WOK\nTOSS", "zh": "颠勺\n起锅"},
  "hud_wok_label": {"en": "WOK", "zh": "锅气"},
  "hud_ff": {"en": "FAST", "zh": "快进"},
  "hud_unlocked": {"en": "UNLOCKED: %s!", "zh": "解锁：%s！"},
  "hud_combo": {"en": "COMBO x%d", "zh": "连击 x%d"},
  "hud_wok_heat": {"en": "WOK HEAT  %d%%", "zh": "锅气  %d%%"},
  "hud_level": {"en": "LV %d", "zh": "等级 %d"},
  "hud_xp": {"en": "XP %d/%d", "zh": "经验 %d/%d"},
  "level_up": {"en": "LEVEL UP!  LV %d", "zh": "升级！Lv %d"},
  "level_up_multi": {"en": "LEVEL UP!  +%d  →  LV %d", "zh": "连升 %d 级！Lv %d"},
  # 主动技能名：十个角色各有专属技能（data/skills.json 的 id → 这里）。
  # 按钮只有 76px 宽，所以这里存的是【短名】（冰镇/穿透/标记…），不是技能全名。
  "skill_frost": {"en": "FROST", "zh": "冰镇"},
  "skill_pierce_shot": {"en": "PIERCE", "zh": "穿透"},
  "skill_quake": {"en": "QUAKE", "zh": "震地"},
  "skill_frost_nova": {"en": "NOVA", "zh": "冰爆"},
  "skill_gust": {"en": "GUST", "zh": "疾风"},
  "skill_coin_rain": {"en": "COINS", "zh": "金币雨"},
  "skill_spike_burst": {"en": "SPIKES", "zh": "尖刺"},
  "skill_mark": {"en": "MARK", "zh": "标记"},
  "skill_combo": {"en": "COMBO", "zh": "连击"},
  "skill_magnet_pull": {"en": "MAGNET", "zh": "磁吸"},
  "skill_sear": {"en": "SEAR", "zh": "灼烧"},
  "skill_grind": {"en": "GRIND", "zh": "碾压"},
  "skill_flashfire": {"en": "HEAT", "zh": "火候"},
  "skill_glacial_burst": {"en": "SHARD", "zh": "冰锥"},
  "skill_magma_fissure": {"en": "OIL", "zh": "滚油"},
  "skill_wind_blade": {"en": "BLADE", "zh": "风刃"},
  "skill_shock_field": {"en": "SHOCK", "zh": "电场"},
  "skill_gold_crash": {"en": "SLAM", "zh": "金砖"},
  "skill_burst_arrow": {"en": "BLAZE", "zh": "爆裂"},
  "skill_char_burst": {"en": "CHAR", "zh": "炭爆"},
  "hud_attack": {"en": "ATK", "zh": "攻击"},

  # ---- 商店 ----
  "shop_title": {"en": "SHOP", "zh": "补给站"},
  "shop_gold": {"en": "GOLD %d", "zh": "金币 %d"},
  "shop_gold_unit": {"en": "Gold", "zh": "金币"},
  "shop_weapon": {"en": "WEAPON", "zh": "武器"},
  "shop_upgrade": {"en": "UPGRADE", "zh": "强化"},
  "shop_sold": {"en": "SOLD", "zh": "已售"},
  "shop_reroll": {"en": "REROLL (%d)", "zh": "刷新 (%d)"},
  "shop_next": {"en": "NEXT WAVE →", "zh": "下一波 →"},
  "shop_slots_full_hint": {"en": "SLOTS FULL — sell one to roll new weapons", "zh": "槽位已满：先卖掉一把，才能刷出新武器"},
  "shop_big_tag": {"en": "★ BIG SALE  −%d%% ALL", "zh": "★ 大促销  全场 −%d%%"},

  # ---- 暂停 ----
  "pause_title": {"en": "PAUSED", "zh": "暂停"},
  "pause_resume": {"en": "RESUME", "zh": "继续"},
  "pause_settings": {"en": "SETTINGS", "zh": "设置"},
  "pause_restart": {"en": "RESTART", "zh": "重开"},
  "pause_quit": {"en": "QUIT TO TITLE", "zh": "退出到标题"},
  "pause_sfx": {"en": "SFX   ", "zh": "音效   "},
  "pause_music": {"en": "MUSIC ", "zh": "音乐 "},
  "pause_stats": {"en": "STATS", "zh": "属性"},

  # ---- 独立属性页 ----
  "stats_title": {"en": "STATS", "zh": "属性"},
  "stats_back": {"en": "BACK", "zh": "返回"},
  "hud_stats": {"en": "STATS", "zh": "属性"},
  "stats_cat_core": {"en": "Combat", "zh": "核心战斗"},
  "stats_cat_econ": {"en": "Economy", "zh": "经济拾取"},
  "stats_cat_wok": {"en": "Wok Toss", "zh": "锅气颠勺"},
  "stats_cat_move": {"en": "Mobility", "zh": "机动闪避"},
  "stat_max_hp": {"en": "Max HP", "zh": "生命上限"},
  "stat_armor": {"en": "Armor", "zh": "护甲"},
  "stat_attack": {"en": "Attack Power", "zh": "攻击力"},
  "stat_speed": {"en": "Move Speed", "zh": "移动速度"},
  "stat_dmg": {"en": "Damage", "zh": "伤害"},
  "stat_rate": {"en": "Attack Speed", "zh": "攻击速度"},
  "stat_range": {"en": "Range", "zh": "射程"},
  "stat_bspd": {"en": "Bullet Speed", "zh": "弹速"},
  "stat_crit": {"en": "Crit Chance", "zh": "暴击率"},
  "stat_critmul": {"en": "Crit Damage", "zh": "暴击伤害"},
  "stat_pierce": {"en": "Pierce", "zh": "穿透"},
  "stat_aoe": {"en": "Area", "zh": "范围"},
  "stat_pellets": {"en": "Extra Pellets", "zh": "额外弹丸"},
  "stat_lifesteal": {"en": "Lifesteal", "zh": "吸血"},
  "stat_regen": {"en": "Regen /s", "zh": "每秒回血"},
  "stat_dodge": {"en": "Dodge", "zh": "闪避"},
  "stat_goldgain": {"en": "Gold Gain", "zh": "金币获取"},
  "stat_pickup": {"en": "Pickup Range", "zh": "拾取半径"},
  "stat_autopick": {"en": "Auto Pickup", "zh": "自动拾取"},
  "stat_fullauto": {"en": "Vacuum Pickup", "zh": "全屏拾取"},
  "stat_wok_pct": {"en": "Wok Gain", "zh": "锅气获取"},
  "stat_wok_dmg": {"en": "Wok Damage", "zh": "颠勺伤害"},
  "stat_wok_knock": {"en": "Wok Knockback", "zh": "颠勺击退"},
  "stat_wok_slow": {"en": "Wok Slow", "zh": "颠勺减速"},
  "stat_wok_charges": {"en": "Wok Charges", "zh": "颠勺充能"},
  "stat_wok_freeze": {"en": "Wok Freeze", "zh": "颠勺冰冻"},
  "stat_wok_poison": {"en": "Wok Poison", "zh": "颠勺毒雾"},
  "stat_wok_burn": {"en": "Wok Burn", "zh": "颠勺灼烧"},
  "stat_wok_shred": {"en": "Wok Shred", "zh": "颠勺破甲"},
  "stat_wok_explode": {"en": "Wok Explode", "zh": "颠勺爆炸"},
  "stat_wok_lifesteal": {"en": "Wok Lifesteal", "zh": "颠勺吸血"},
  "stat_wok_gold": {"en": "Wok Gold", "zh": "颠勺金币"},
  "stat_wok_refund": {"en": "Wok Refund", "zh": "颠勺返还"},
  "stat_wok_double": {"en": "Wok Double", "zh": "双重颠勺"},
  "stat_wok_vortex": {"en": "Wok Vortex", "zh": "颠勺漩涡"},
  "stat_wok_chain": {"en": "Wok Chain", "zh": "颠勺连锁"},
  "stat_wok_elite": {"en": "Elite Wok Chance", "zh": "精英颠勺率"},
  "stat_dash_cd": {"en": "Dash Cooldown", "zh": "冲刺冷却"},
  "stat_dash_dist": {"en": "Dash Distance", "zh": "冲刺距离"},
  "stat_ifr": {"en": "Invuln Time", "zh": "无敌帧"},
  "stat_homing_pct": {"en": "Homing", "zh": "制导强化"},
  "stat_knock_pct": {"en": "Knockback", "zh": "击退强化"},
  "stat_low_hp_dmg": {"en": "Berserk", "zh": "背水一战"},
  "stat_wave_heal": {"en": "Wave Mend", "zh": "波末回血"},
  "stat_ricochet": {"en": "Ricochet", "zh": "弹墙"},
  "stat_shop_discount": {"en": "Haggler", "zh": "砍价"},
  "stat_hit_boost": {"en": "Adrenaline", "zh": "受击爆发"},
  "stat_skill_power": {"en": "Skill Power", "zh": "技能强度"},
  "stat_skill_cd": {"en": "Skill Cooldown", "zh": "技能冷却"},
  "syn_signature": {"en": "SIGNATURE", "zh": "本命"},
  "syn_bond": {"en": "BOND", "zh": "羁绊"},
  "syn_variety": {"en": "OMNIVORE", "zh": "杂食"},
  "char_form": {"en": "FORM", "zh": "形态"},
  "syn_next": {"en": "%d more", "zh": "还差 %d 件"},
  "syn_max": {"en": "MAX", "zh": "已满"},

  # ---- 标题 ----
  "title_sub": {"en": "", "zh": "萝 卜 突 围"},
  "title_tag": {"en": "Survive the veggie apocalypse", "zh": "在蔬菜大浩劫中活下去"},
  "title_best": {"en": "BEST %d  ·  WAVE %d", "zh": "最佳 %d  ·  波次 %d"},
  "title_first": {"en": "FIRST RUN — GOOD LUCK", "zh": "首次出击 — 祝好运"},
  "title_next": {"en": "NEXT UNLOCK: %s — %d more %s", "zh": "下一个解锁：%s — 还差 %d %s"},
  "title_how": {"en": "Drag the joystick to move\nWeapons fire on their own\nClear waves · grab gold · get stronger",
                "zh": "拖动摇杆移动\n武器自动开火\n清波次 · 捡金币 · 变强"},
  "title_pick": {"en": "CHOOSE YOUR VEG", "zh": "选择你的蔬菜"},
  "mode_label": {"en": "RUN LENGTH", "zh": "单局时长"},
  "mode_short": {"en": "SHORT", "zh": "短局"},
  "mode_classic": {"en": "CLASSIC", "zh": "经典"},
  "mode_endless": {"en": "ENDLESS", "zh": "无尽"},
  "mode_waves": {"en": "%d waves", "zh": "%d 波"},
  "mode_forever": {"en": "no end", "zh": "打不通关"},
  "mode_minutes": {"en": "~%d min", "zh": "约 %d 分钟"},
  "title_start": {"en": "START", "zh": "开始"},

  # ---- 结算 ----
  "victory_title": {"en": "VICTORY!", "zh": "通关！"},
  "victory_stat": {"en": "Cleared Wave %d\n%d Kills  ·  %d Gold\nSCORE %d",
                   "zh": "通关第 %d 波\n击杀 %d  ·  金币 %d\n得分 %d"},
  "victory_again": {"en": "PLAY AGAIN", "zh": "再来一局"},
  "victory_continue": {"en": "CONTINUE ENDLESS", "zh": "继续无尽"},
  "hud_endless": {"en": "ENDLESS WAVE %d", "zh": "无尽波次 %d"},
  "hud_final_boss": {"en": "FINAL BOSS!", "zh": "终局首领！"},
  "death_title": {"en": "GAME OVER", "zh": "游戏结束"},
  "death_stat": {"en": "Reached Wave %d\n%d Kills  ·  %d Gold\nSCORE %d",
                 "zh": "到达第 %d 波\n击杀 %d  ·  金币 %d\n得分 %d"},
  "death_again": {"en": "PLAY AGAIN", "zh": "再来一局"},

  # ---- 角色选择 ----
  "char_base": {"en": "BASE", "zh": "基础"},

  # ---- 开局选武器 ----
  "pick_weapon_title": {"en": "CHOOSE YOUR WEAPON", "zh": "选择初始武器"},
  "pick_weapon_hint": {"en": "Pick ONE starter. Pistol stays as your backup.",
                       "zh": "选 1 把开局武器 · 手枪作为保底一同携带"},
  "pick_weapon_confirm": {"en": "GO!", "zh": "出发！"},
  "pick_weapon_back": {"en": "BACK", "zh": "返回"},
  "pick_weapon_sel": {"en": "SELECTED", "zh": "已选"},
  "pick_weapon_loadout": {"en": "LOADOUT: %s + Pistol", "zh": "本局阵容：%s + 手枪"},

  # ---- 商店（补全标签）----
  "shop_new": {"en": "NEW", "zh": "新武器"},
  "shop_merge": {"en": "MERGE +1", "zh": "合成 +1"},
  "shop_merge_btn": {"en": "MERGE", "zh": "合成"},
  "shop_sell": {"en": "SELL", "zh": "售"},
  "shop_sell_btn": {"en": "SELL +", "zh": "卖出 +"},
  "shop_keep_one": {"en": "Keep at least one weapon", "zh": "至少保留一把武器"},
  "shop_myweapons": {"en": "YOUR WEAPONS", "zh": "我的武器"},
  "shop_full": {"en": "SLOTS FULL", "zh": "槽位已满"},
  "shop_rarity": {"en": "RARITY", "zh": "稀有度"},

  # ---- 统计名（解锁进度） ----
  "stat_kills": {"en": "kills", "zh": "击杀"},
  "stat_gold": {"en": "gold", "zh": "金币"},
  "stat_wave": {"en": "wave", "zh": "波次"},
  "stat_wins": {"en": "wins", "zh": "通关"},
}

func _ready() -> void:
  # autoload 顺序保证 Settings 已 _ready；这里直接读已加载的语言偏好
  if Settings != null:
    locale = Settings.get_language()
  else:
    locale = "en"

# UI 静态文案
func t(key: String) -> String:
  var e = UI.get(key, {})
  if e == null or e.is_empty():
    return key
  var d: Dictionary = e
  return str(d.get(locale, d.get("en", key)))

# 数据条目按语言的名称字段（默认 en/zh 两键；调用方可指定）
func pick(d: Dictionary, en_k: String = "en", zh_k: String = "zh") -> String:
  if locale == "zh":
    return str(d.get(zh_k, d.get(en_k, "")))
  return str(d.get(en_k, d.get(zh_k, "")))

# 数据条目按语言的描述字段：en 用 tip_en，zh 用 tip
func tip(d: Dictionary) -> String:
  if locale == "zh":
    return str(d.get("tip", d.get("tip_en", "")))
  return str(d.get("tip_en", d.get("tip", "")))

# 解锁进度里的统计名
func stat_label(t: String) -> String:
  var k := ""
  match t:
    "total_kills": k = "stat_kills"
    "total_gold": k = "stat_gold"
    "best_wave": k = "stat_wave"
    "wins": k = "stat_wins"
    _: k = "stat_" + t
  return t(k)

# 切换语言：写 Settings 持久化 + 通知各界面
func set_locale(code: String) -> void:
  if code != "en" and code != "zh":
    return
  if code == locale:
    return
  locale = code
  Settings.set_language(code)
  locale_changed.emit(locale)
