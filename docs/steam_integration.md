# Steam 接入与 v1.0 上架指南（TURNIP TROUBLE / 萝卜突围）

> 本文件面向**开发者本人**（需 Steam 账号与本地环境）。AI 已完成代码侧技术准备，
> 但涉及账号、付费、二进制 SDK、商店后台审核的部分无法代劳，必须你亲自完成。

## 一、代码侧已完成的技术准备（AI 做的）

- `autoload/Steam.gd`：Steam API 安全封装层。检测 GodotSteam 的 `Steam` singleton，
  未挂载时**全部方法 no-op**，游戏在任何环境都不崩。
- `steam_appid.txt`：占位 `0`，上线前改成你的真实 AppID。
- `scenes/Game.gd` 的 `_finish_run()` 已调用 `Steam.record_run(wave, kills, gold, won)`，
  通关自动解锁 `first_clear` 成就、写入 `max_wave` / `total_kills` / `total_gold` 统计。
- `scripts/build_steam.sh`：桌面导出骨架（Linux/Windows），自动把 `steam_appid.txt` 带进包根。
- `web/store-assets/`：已生成的商店图（capsule / header / 5 张 screenshot / background）。

## 二、你需要做的（按顺序）

1. **注册 Steamworks 开发者**
   一次性 $100（不可退），在 partner.steamgames.com 完成。

2. **创建应用，拿到 AppID**
   在 Steamworks 后台「Create a new app」→ 拿到数字 AppID → 写入 `steam_appid.txt`
   （替换占位 `0`）。本地测试可用 Valve 的测试 AppID `480`（Spacewar）。

3. **接入 GodotSteam GDExtension**
   从 GodotSteam 发布页下载与你 Godot 4.3 匹配的版本，解压到 `addons/godotsteam/`，
   在项目设置里启用该 GDExtension（`project.godot` 出现 `[gdextension]` 段即成功）。
   注意：Web 构建**不需要**也不能包含 GodotSteam（仅桌面端）。

4. **配置桌面导出预设**
   在 Godot 编辑器「项目 → 导出」添加 **Linux/X11** 与 **Windows** 预设（沙箱无 GUI，
   需你在本地编辑器点选；`web/build` 的 Web 预设已就绪）。
   然后跑 `bash scripts/build_steam.sh` 产出 `build/steam/` 包。

5. **在 Steamworks 后台定义 Achievements / Stats**
   至少建：
   - Achievement `first_clear`（首次通关）
   - Stat `max_wave`（int）、`total_kills`（int）、`total_gold`（int）
   名字需与 `Steam.gd` 里的调用一致（如有差异，改 `Steam.gd` 即可，已用 `has_method` 保护）。

6. **上传商店素材**
   把 `web/store-assets/` 里的图上传到商店页：
   - capsule `capsule_616x353.png`
   - header `header_460x215.png`
   - 5 张 screenshot `1280x720`
   - background `1280x720`
   （另需社区图标、库海报 hero 等，可在后台按需补，非阻塞）

7. **定价 / 地区 / 语言 / 分级**
   定价（建议首发折扣）、发行地区、简体中文 + English、IARC/ESRB 分级问卷。

8. **上传构建到 Depot**
   用 `build_steam.sh` 产物，Steamworks「SteamPipe」上传到对应 depot。

9. **提交审核**
   先做**抢先体验（Early Access）**风险更低；内容稳定后转正式 1.0。

## 三、上架待办清单（必须开发者决策/操作）

| 项 | 状态 | 谁做 |
|---|---|---|
| Steamworks 开发者账号 + $100 | ❌ 未注册 | 你 |
| AppID（填 steam_appid.txt） | ❌ 占位 0 | 你 |
| GodotSteam GDExtension 下载接入 | ❌ | 你（本地） |
| Linux/Windows 导出预设 | ❌ | 你（本地编辑器） |
| Achievements/Stats 定义 | ❌ 后台 | 你 |
| capsule/header/screenshots 上传 | ✅ 图已生成 | 你上传 |
| 定价 / 地区 / 语言 / 分级 | ❌ | 你 |
| 构建上传 Depot | ❌ | 你 |
| 提交审核（EA / 1.0） | ❌ | 你 |

## 四、测试建议

- 本地用 `480`（Spacewar）跑通 `Steam.record_run` → 看 Steam 客户端是否弹出成就/统计。
- 确认 `steam_appid.txt` 与 exe 同目录（build_steam.sh 已 cp）。
- Web 构建不接 Steam，行为不受影响（封装层 no-op）。
