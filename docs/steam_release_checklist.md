# Steam 上架发行清单（TURNIP TROUBLE / 萝卜突围）

> 配合 `docs/steam_integration.md` 使用。本文件聚焦**分级 / 定价 / 素材 / 上线前核对**，
> 代码侧与账号/SDK 操作见前者。以下带 ❌ 的项均需你（开发者）亲自完成。

---

## 一、年龄分级建议（ESRB / PEGI / IARC）

| 机构 | 建议等级 | 理由 |
|---|---|---|
| **ESRB** | **Everyone 10+** | 卡通暴力（蔬菜互殴、无流血/无死亡描写），含"厨房武器"喜剧化战斗，无脏话/无敏感内容。若想更宽可申 **E**。 |
| **PEGI** | **7** 或 **12** | 卡通暴力，建议 **PEGI 7**（轻松幽默）；若后台判定偏严选 **PEGI 12** 更稳。 |
| **IARC** | 对应 "Mild Fantasy Violence" | Steam 国区/通用走 IARC 问卷，勾卡通奇幻暴力即可，无需血腥/写实暴力选项。 |

- 无内购随机性争议（武器靠累计进度解锁，非开箱）→ 分级问卷可如实填"无 loot box"。
- Web 版（网页出海）海外平台分级通常沿用同口径，单独确认目标平台要求。

## 二、定价建议

- **参考区间**：独立 Roguelite 单人小品，建议首发 **$4.99 – $9.99**（¥18 – ¥68 国区）。
  - 保守切入：$4.99 降低决策门槛，配合首发折扣冲量。
  - 内容厚度够（12 武器 + Roguelite 进程 + Boss）可定 $7.99 – $9.99。
- **免费 + 可选 DLC**：若走免费基底，可做"角色包 / 武器包"DLC（注意 DLC 也需各自分级与定价）。
- **地区定价**：国区走人民币定价（¥18–¥68）；用 Steam 推荐地区汇率自动换算，重点市场（美/欧/中/日）手动核对。
- **首发折扣**：建议 10%–20% 限时折扣（新游戏上线前 2–4 周），提升初期曝光与评测积累。

## 三、商店图清单（来自 `web/store-assets/`，模块 3 已生成 8 张）

| 文件名 | 尺寸 | 用途 |
|---|---|---|
| `capsule_616x353.png` | 616×353 | 主胶囊图（商店列表 / 搜索结果主视觉） |
| `header_460x215.png` | 460×215 | 页眉图（商店页顶部横幅） |
| `screenshot_01_title.png` | 1280×720 | 截图 1：标题/主菜单 |
| `screenshot_02_combat.png` | 1280×720 | 截图 2：战斗场面（武器+锅气） |
| `screenshot_03_shop.png` | 1280×720 | 截图 3：补给站/强化界面 |
| `screenshot_04_characters.png` | 1280×720 | 截图 4：角色/武器选择 |
| `screenshot_05_boss.png` | 1280×720 | 截图 5：Boss 波 |
| `background_1280x720.png` | 1280×720 | 商店页背景图 |

> 额外可用素材（非阻塞，按需补）：`art/store/capsule_small.png`（小胶囊/库图标）、`art/store/capsule_header.png`（库海报）。
> 后台还可能要：社区图标（正方形）、库英雄图（1920×620）、推广图——按后台提示上传即可。

## 四、上线前最终核对项

| # | 项 | 状态 | 谁做 |
|---|---|---|---|
| 1 | `steam_appid.txt` 填入真实 AppID（替换占位 `0`；本地自测可用 `480`） | ❌ | 你 |
| 2 | 下载并接入 GodotSteam GDExtension（匹配 Godot 4.3），`project.godot` 出现 `[gdextension]` 段 | ❌ | 你（本地） |
| 3 | Linux/X11 与 Windows 导出预设配置（Web 不需要 GodotSteam） | ❌ | 你（本地编辑器） |
| 4 | 后台定义 Achievements：`first_clear`（首次通关） | ❌ | 你（后台） |
| 5 | 后台定义 Stats：`best_wave`/`total_kills`/`total_gold`/`wins`（int，名字须与 `Steam.gd` 一致） | ❌ | 你（后台） |
| 6 | 上传 8 张商店图（见第三节）到商店页 | ❌ 图已生成 | 你上传 |
| 7 | 分级问卷（ESRB/PEGI/IARC，见第一节） | ❌ | 你 |
| 8 | 定价 / 发行地区 / 语言（简体中文 + English） | ❌ | 你 |
| 9 | `scripts/build_steam.sh` 产出 `build/steam/` 包（已 cp `steam_appid.txt`） | ❌ | 你（本地跑） |
| 10 | SteamPipe 上传构建到对应 Depot | ❌ | 你 |
| 11 | 提交审核（建议先 Early Access，再转 1.0） | ❌ | 你 |

### 代码侧已就绪（无需你再做）
- `autoload/Steam.gd` 安全封装：未挂载 GodotSteam 时全 no-op，游戏不崩。
- `scenes/Game.gd` 的 `_finish_run` 已正确调用 `Steam.record_run(...)`，通关 `won=true` 时解锁 `first_clear`；统计写**累计值**（取自 `SaveMgr.data`），与 `unlocks.json` 进度对齐。
- `docs/steam_store_copy.md` 提供商店文案（英/中短+长描述）。
