# 推币机的狂欢（COIN CARNIVAL）

> **手机竖屏 · 2.5D 霓虹街机风 · 推币物理 × 满屏数字肉鸽**
> 基于 UrhoX（Lua 5.4 + `urhox-libs/UI` + NanoVG + 自研零 GC 对象池 2.5D 物理）打造。

---

## 核心特色与玩法

1. **真实街机推币手感 + 零卡顿物理**：
   - 上部摆动落币口 + 错位双排霓虹钉阵 + 锁相同步移动中奖门；下层梯形 2.5D 往复推台与双侧侧漏缝。
   - **140 枚同屏硬币对象池上限**，满台溢出触发**超频回收集分**；卡死保险丝防止重币死卡弹珠钉阵；内置 60 FPS 全特效压测均值约 `1.575 ms/帧`（PC 模拟环境下 3600 帧仅 `5671 ms`）。
2. **双轴乘区 × 满屏暴击飙分**：
   - 得分公式 `Chips × Mult × ComboMultiplier × CritMultiplier`，伴随分批爆音与暴击顿帧、屏幕微震及数字跳字。
   - 蓄满 **狂欢槽（Fever）** 激活 8 秒+ 狂欢金币雨、双倍倍率与 `1.75x` 推板加速；支持一二三幕递增万/千万/亿级爆分与无尽波次挑战。
3. **6 大家族 × 16 枚基础/进阶/传说币 × 6 种融合进化 × 20 件遗物**：
   - 6 大家族（`财富`、`爆破`、`连锁`、`倾泻`、`聚能`、`狂欢`）均有 **2 / 4 / 6** 三档协同。
   - 支持 **三合一升星**（Lv1 → Lv3）与整备工坊 **双币融合进化**（点金圣王、雷神之锤、超新星爆、无限分身、奇点涡轮、狂欢大满贯）。
4. **3 幕分支战役 + 3 大机械 Boss + 20 档超频难度 + 每日挑战**：
   - 含普通/精英战、霓虹商店、整备工坊、6 个奇遇事件、遗物宝箱与 3 位关底 Boss（`铁闸庄家`、`熔金巨轮`、`终极吞金兽`）。
   - 支持局外图鉴与最多禁用 3 个冷门条目的图鉴禁用池，以及 20 档渐进超频难度。
5. **程序音画完整兜底 + 美术零代码热替换**：
   - 全部硬币、遗物、机台与 UI 默认均由 [`Skin.lua`](scripts/game/Skin.lua) 与 [`Art.lua`](scripts/game/Art.lua) 程序化矢量高光渲染；另附完整生成的 **20 个游戏音效 WAV + 4 组双音轨动态 BGM（基础 + 狂欢鼓点层）**。
   - 后期如需换为成品美术贴图，可参照 [`docs/ASSET_PROMPTS.md`](docs/ASSET_PROMPTS.md) 生成 PNG 并直接放入 `assets/image/...`。

---

## 爽感特效系统（2026-11 重构）

“看见增益 → 增益飞向目标 → 目标被砸响”三段式反馈，所有特效统一在屏幕空间绘制（3D / 2D 舞台共用）：

| 模块 | 作用 |
|---|---|
| [`Fx.lua`](scripts/game/Fx.lua) | 分级爆分飘字（近邻合并滚数、T4+ 合并为一个持续累加的大数字、×倍率戳、暴击角标）、火花/星光/翻转金币/彩纸粒子、三层锯齿闪电、中央重磅印章队列、飞币入账、倍率令牌、全屏闪光与狂欢暗角、镜头冲击与机台点光闪烁信号；`SetQuality(0.5)` 低画质档 |
| [`Stage.lua`](scripts/game/Stage.lua) | 机台顶棚“总倍率”霓虹招牌（实时增益芯片：连击/狂欢/老虎机/印钞，点击查看公式）、真实滚动老虎机、狂欢能量玻璃管、连击计时光环、传说币闪烁星光；锚点取自 3D 投影，随屏幕比例自适应 |
| [`JuiceWidgets.lua`](scripts/game/JuiceWidgets.lua) | `CashCounter` 顶栏滚动现金计数器（飞币砸中冲击 + 金光 + 产值上涨绿闪）；`FxLayer` 顶层特效层 |
| [`Machine3D.lua`](scripts/game/Machine3D.lua) | 大事件 FOV 冲击、点光按事件变色闪烁、狂欢彩虹霓虹循环、热度驱动跑马灯速度、HUD 屏幕锚点 |

飘字分级以**不含临时加成的基准产值**（`Tycoon:GetBaselineCPS()`）为参照：倍率越高，同一枚币爆出的字越大越炸，倍率加成可以被直接“看见”。

## 目录结构

```text
推币机的狂欢/
├── .project/                  # TapTap Maker 项目配置（竖屏、单机模式、资源索引）
├── docs/
│   ├── GDD.md                 # 完整策划与数值设计文档
│   └── ASSET_PROMPTS.md       # 风格圣经 + 游戏内贴图 1:1 替换提示词 + 宣发三件套提示词
├── scripts/
│   ├── main.lua               # 入口（Start / HandleUpdate / SetGamePaused / Stop）
│   ├── game/
│   │   ├── Config.lua         # 全局数值、16+6+3 币种、20 遗物、6 事件、3 幕目标、20 难度
│   │   ├── Number.lua         # 万/亿/兆中文大数字格式与平滑插值
│   │   ├── Physics.lua        # 140 池位定制 2.5D 推台/钉阵/中奖门物理与卡死保险丝
│   │   ├── Roster.lua         # 投币仓构筑、三合一、双币进化、2/4/6 协同与遗物查询
│   │   ├── Route.lua          # 三幕 6 层分岔战役路线图生成
│   │   ├── Run.lua            # 单局战役状态机、Boss 机制、经济与断点快照导出恢复
│   │   ├── Skin.lua           # 霓虹配色、矢量控件皮肤与 assets/image 自动热替换探针
│   │   ├── Art.lua            # 2.5D 硬币、钉子、图标矢量渲染与贴图优先绘制器
│   │   ├── Fx.lua             # 爽感特效总线：分级合并飘字/倍率令牌/飞币入账/印章/粒子/闪电
│   │   ├── JuiceWidgets.lua   # 滚动现金计数器 + 顶层特效层
│   │   ├── Stage.lua          # 舞台自定义 Widget（机台/推台/防侧漏边栏/点击连发/引导）
│   │   ├── Widgets.lua        # NeoFrame / NeoButton / NeoIcon / NeoBar 等封装组件
│   │   ├── Hud.lua            # 主菜单 / 三段式战斗 HUD / 三选一弹窗 / 结算弹窗
│   │   ├── CampaignHud.lua    # 分岔路线图 / 3 列商店 / 整备工坊 / 奇遇事件 / 宝箱页
│   │   ├── CodexHud.lua       # 投币仓双页签 / 狂欢图鉴4页签+禁用池 / 20档难度弹窗
│   │   ├── SettingsHud.lua    # 总设置（开关、双端保存时间与红字失败提示、兑换码、防覆盖框）
│   │   ├── SaveManager.lua    # 原子本地档 + 云端 3 键分包（30s/120s 自动保存 + 换设备防覆盖）
│   │   ├── RedeemCodes.lua    # 内置兑换码系统与防重领校验
│   │   ├── Sfx.lua            # 16 通道音效池、45ms 同音节流与左右声道平移
│   │   └── Music.lua          # 双音轨动态 BGM（连击/狂欢渐入鼓点 + 弹窗 0.4x 压低）
│   └── Tests/                 # 真机 UrhoXRuntime 自动化与多界面截图验收脚本
├── assets/
│   └── audio/                 # 20 个 WAV 音效与 8 个双音轨 BGM 音频
├── devtools/
│   └── gen_audio.js           # 程序合成 16-bit WAV 音效与双轨 BGM 生成器
└── tests/                     # 独立 Lua 5.4（lupa）单测、3600 帧压测与平衡模拟脚本
```

---

## 内置兑换码

在「设置」页面输入即可领取（不区分大小写，每人每档限领 1 次）：

| 兑换码 | 奖励内容 |
|---|---|
| `CARNIVAL2026` | 50 金券 + 777 轮盘币 |
| `COIN888` | 88 金券 + 标准金币 |
| `FEVER666` | 40 金券 + 下一局满狂欢开局 |

---

## 本地测试与真机预览验证命令

> 以下命令全部于本地环境执行，不触发任何云端构建或仓库推送。

### 1. 运行核心单元测试与 3600 帧性能压测（`lupa` / Lua 5.4）
```powershell
$PY = "C:\Users\Administrator\.taptap-maker\python\uv\cpython-3.12-windows-x86_64-none\python.exe"
& $PY "c:\Users\Administrator\Desktop\推币机的狂欢\tests\run_lua.py" "c:\Users\Administrator\Desktop\推币机的狂欢\tests\test_core.lua"
& $PY "c:\Users\Administrator\Desktop\推币机的狂欢\tests\run_lua.py" "c:\Users\Administrator\Desktop\推币机的狂欢\tests\stress_perf.lua"
& $PY "c:\Users\Administrator\Desktop\推币机的狂欢\tests\run_lua.py" "c:\Users\Administrator\Desktop\推币机的狂欢\tests\sim_balance.lua"
```

### 2. UrhoXRuntime 竖屏引擎验证与截图验收（支持 `--mode both`）
```powershell
$TM = "C:\Users\Administrator\AppData\Roaming\npm\node_modules\@taptap\maker\bin\taptap-maker"
node $TM preview validate --target-dir "c:\Users\Administrator\Desktop\推币机的狂欢" --mode both --entry "main.lua" --validate-frames 180 --screenshot-frame 150 --width 450 --height 900 --nosound --output-dir "c:\Users\Administrator\Desktop\推币机的狂欢\validation\final_main" --json
```
同理可将 `--entry` 替换为 `Tests/FullGameValidation.lua`、`Tests/ShotMenu.lua`、`Tests/ShotMap.lua`、`Tests/ShotShop.lua`、`Tests/ShotCodex.lua`、`Tests/ShotSettings.lua` 检验对应页面。

### 3. 启动本地交互预览窗口亲自试玩
```powershell
node $TM preview --target-dir "c:\Users\Administrator\Desktop\推币机的狂欢" --width 450 --height 900
```
