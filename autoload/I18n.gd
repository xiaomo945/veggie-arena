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
  "settings_move": {"en": "Move Speed", "zh": "移动速度"},
  "settings_quality": {"en": "Quality", "zh": "画质"},
  "quality_low": {"en": "Low", "zh": "低"},
  "quality_mid": {"en": "Medium", "zh": "中"},
  "quality_high": {"en": "High", "zh": "高"},
  "settings_shake": {"en": "Screen Shake", "zh": "震屏"},
  "settings_particles": {"en": "Particles", "zh": "粒子"},
  "settings_fps": {"en": "Target FPS", "zh": "帧率目标"},
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

  # ---- 商店 ----
  "shop_title": {"en": "SHOP", "zh": "补给站"},
  "shop_gold": {"en": "GOLD %d", "zh": "金币 %d"},
  "shop_gold_unit": {"en": "Gold", "zh": "金币"},
  "shop_weapon": {"en": "WEAPON", "zh": "武器"},
  "shop_upgrade": {"en": "UPGRADE", "zh": "强化"},
  "shop_sold": {"en": "SOLD", "zh": "已售"},
  "shop_reroll": {"en": "REROLL (%d)", "zh": "刷新 (%d)"},
  "shop_next": {"en": "NEXT WAVE →", "zh": "下一波 →"},

  # ---- 暂停 ----
  "pause_title": {"en": "PAUSED", "zh": "暂停"},
  "pause_resume": {"en": "RESUME", "zh": "继续"},
  "pause_settings": {"en": "SETTINGS", "zh": "设置"},
  "pause_restart": {"en": "RESTART", "zh": "重开"},
  "pause_quit": {"en": "QUIT TO TITLE", "zh": "退出到标题"},
  "pause_sfx": {"en": "SFX   ", "zh": "音效   "},
  "pause_music": {"en": "MUSIC ", "zh": "音乐 "},

  # ---- 标题 ----
  "title_sub": {"en": "", "zh": "萝 卜 突 围"},
  "title_tag": {"en": "Survive the veggie apocalypse", "zh": "在蔬菜大浩劫中活下去"},
  "title_best": {"en": "BEST %d  ·  WAVE %d", "zh": "最佳 %d  ·  波次 %d"},
  "title_first": {"en": "FIRST RUN — GOOD LUCK", "zh": "首次出击 — 祝好运"},
  "title_next": {"en": "NEXT UNLOCK: %s — %d more %s", "zh": "下一个解锁：%s — 还差 %d %s"},
  "title_how": {"en": "Drag the joystick to move\nWeapons fire on their own\nClear waves · grab gold · get stronger",
                "zh": "拖动摇杆移动\n武器自动开火\n清波次 · 捡金币 · 变强"},
  "title_pick": {"en": "CHOOSE YOUR VEG", "zh": "选择你的蔬菜"},
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
