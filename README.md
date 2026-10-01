# 🥕 veggie-arena

> 暂定名：**《萝卜突围》TURNIP TROUBLE**
> 手机竖屏竞技场生存 Roguelite —— 怪物从四面八方涌来，武器自动开火，你只管跑位。

---

## 当前状态

**v0.1 · 文档阶段**（2026-09-30）

已完成：
- ✅ 需求文档、工程约束、权限清单、模块与路线图
- ✅ HTML5 原型（P0 全部功能已验证，变向响应 33ms）
- ✅ 仓库骨架

进行中：
- ⬜ Godot 工程骨架 + core 逻辑层 + 测试框架

卡在：
- 🔴 GitHub 令牌未授权 —— **代码目前只存在于沙箱，这是最大风险**

---

## 文档索引（按顺序读）

| 文档 | 内容 |
|---|---|
| [01_需求文档](docs/01_需求文档.md) | 做什么、给谁玩、为什么能做、功能清单 |
| [02_工程约束与规范](docs/02_工程约束与规范.md) | **十条硬规则**、目录结构、命名、git 流程 |
| [03_权限与环境清单](docs/03_权限与环境清单.md) | 开工前需要你开放的**全部权限** |
| [04_模块结构与路线图](docs/04_模块结构与路线图.md) | 模块划分、接口、施工顺序 |

---

## 怎么跑

### 跑测试（不需要打开游戏）

```bash
bash scripts/check.sh
```

### 跑 Godot 编辑器（本机）

需要你本机安装 Godot 4.3：https://godotengine.org/download

### 导出网页版

用 Godot 编辑器：Project → Export → Web，产物覆盖写到 `web/build/`（唯一在线产物，不进 git）。
本地一键自检（语法 + 启动 + 单测）：`bash scripts/check.sh`

---

## 三条最重要的规则

1. **数值只改 `data/*.json`，不动代码**
2. **一次只做一个功能，测完再做下一个**
3. **`core/` 不许引用任何画面相关的东西** —— 只有这样才能自动测试

详见 [02_工程约束与规范](docs/02_工程约束与规范.md)。

---

## 项目简介 / Project Overview

**《萝卜突围》TURNIP TROUBLE** 是一款 **竖屏单手竞技场生存 Roguelite**（对标《Brotato》）。
你扮演一颗拿中式厨具打架的萝卜：左手虚拟摇杆走位，右手武器**自动开火**，靠走位与冲刺闪避撑过 20 波敌人。
完全**免费、浏览器即开即玩**，即将登陆 Steam（支持手柄 / Steam Deck）。

**TURNIP TROUBLE** is a **portrait, one-handed arena survival roguelite** (a spiritual cousin of *Brotato*).
You play a turnip wielding Chinese kitchenware: left thumb steers, your weapons **auto-fire**, and you survive 20 waves with positioning and dashes.
It's **free, plays instantly in the browser**, and is coming to Steam (controller / Steam Deck support).

主打卖点 / Key hooks：
- 🥕 中式厨房幽默 + 明亮卡通蔬菜画风 / Chinese-kitchen humor, bright cartoon-veggie art
- 🔪 12 种厨具武器（菜刀/签子/汤勺/茶壶/搅拌机/高压锅…）/ 12 kitchen weapons
- 💨 冲刺闪避（按钮 / 手柄 A / RT，带无敌帧）/ Dash dodge with i-frames
- 🍳 招牌「颠勺」全屏翻盘 / Signature Wok Toss screen-clear
- 🥔 4 个可选角色（萝卜/土豆/番茄/辣椒），各有取舍 / 4 trade-off characters
- 🆓 免费、无需下载 / Free, no download

---

## 玩法与操作 / Gameplay & Controls

| 操作 / Action | 触屏 / Touch | 手柄 / Gamepad |
|---|---|---|
| 移动 / Move | 左侧虚拟摇杆（或按住屏幕拖动）/ Left virtual joystick (or drag) | 左摇杆 / Left stick |
| 开火 / Fire | 自动 / Automatic | 自动 / Automatic |
| 冲刺闪避 / Dash (i-frames) | 右下「DASH」按钮 / DASH button | **A** 或 **RT** |
| 颠勺 / Wok Toss | 锅气满后「WOK TOSS」按钮 / WOK TOSS button | 对应按键 / mapped key |
| 商店 / Shop | 每波之间 / Between waves | 同 / Same |

单局约 20 波、每波 ~20 秒：走位聚怪 → 自动开火 → 捡金币 → 波间商店买装备/随机强化 → 攒满锅气放「颠勺」清场。

A run is ~20 waves of ~20s each: kite the swarm → auto-fire → collect coins → shop for weapons/upgrades between waves → fill Wok Heat and unleash the Wok Toss.

---

## 技术栈 / Tech Stack

- **引擎 / Engine:** Godot 4.3
- **语言 / Language:** GDScript
- **平台 / Platforms:** Web（HTML5，已上线可玩）、即将 Steam（手柄 / Steam Deck）
- **架构 / Architecture:** `core/` 纯逻辑层（可自动化测试，不引用任何画面），`data/*.json` 驱动数值，`scenes/`+`scripts/` 负责表现

---

## 本地运行 / Run Locally

```bash
# 1) 克隆仓库 / Clone
git clone <your-repo-url> veggie-arena
cd veggie-arena

# 2) 用 Godot 4.3 打开工程 / Open with Godot 4.3
#    下载 / Download: https://godotengine.org/download
#    启动器中选择本目录的 project.godot
#    In the Godot Project Manager, open the project.godot in this folder.

# 3) 跑测试（无需打开游戏）/ Run tests without launching the game
bash scripts/check.sh
```

---

## 构建网页版 / Build Web

Godot 已配置好 `export_presets.cfg` 的 Web 预设，产物写入 `web/build/`（唯一在线产物，不进 git）。

```bash
# 无头导出发布版 Web（需本机安装 Godot 4.3 并加入 PATH）/ Headless release export
godot --headless --export-release "Web"
```

本地一键自检（语法 + 启动 + 单测）：`bash scripts/check.sh`

---

## 在线试玩 / Play Online

🎮 **https://aacc9a81e890dab49.app.workbuddy.host**

免费、浏览器即开即玩，无需下载安装。
Free to play in your browser — no download, no install.

---

## 目录结构 / Directory Structure

```
veggie-arena/
├── project.godot          # Godot 工程配置
├── export_presets.cfg     # 导出预设（含 Web）
├── core/                  # 纯逻辑层（可测试，不引用画面）
├── autoload/              # 全局单例（GameManager 等）
├── data/                  # 数值配置（*.json，改数值只动这里）
├── entities/              # 角色 / 敌人 / 武器实体
├── scenes/                # 场景（菜单/战斗/商店/UI）
├── scripts/               # 脚本（非场景逻辑）
├── ui/                    # UI 相关
├── art/                   # 美术资源（卡通蔬菜 + 厨房）
├── fonts/                 # 字体
├── tests/                 # 自动化测试
├── web/                   # Web 产物与落地页
│   ├── build/             # 导出的网页版（不进 git）
│   └── landing/index.html # 落地页（含 SEO / 多语言）
├── docs/                  # 需求 / 规范 / 路线图（见下）
└── scripts/               # check.sh 等工程脚本
```

文档索引 / Docs: [`docs/01_需求文档.md`](docs/01_需求文档.md) · [`02_工程约束与规范.md`](docs/02_工程约束与规范.md) · [`03_权限与环境清单.md`](docs/03_权限与环境清单.md) · [`04_模块结构与路线图.md`](docs/04_模块结构与路线图.md) · [`docs/steam_store.md`](docs/steam_store.md)（Steam 文案）

---

## 贡献说明 / Contributing

1. Fork 并 clone 本仓库 / Fork & clone the repo.
2. 数值调整**只改 `data/*.json`**，不要动逻辑代码 / Change **only `data/*.json`** for balance.
3. 一次只做一个功能，完成后跑 `bash scripts/check.sh` / One feature at a time; run `bash scripts/check.sh`.
4. `core/` 不得引用任何画面相关代码，保证可自动测试 / `core/` must stay render-free for testability.
5. 提交前确认 `web/build/` 不进 git（已在 `.gitignore`）/ Keep `web/build/` out of git (see `.gitignore`).

详见 [02_工程约束与规范](docs/02_工程约束与规范.md)。
