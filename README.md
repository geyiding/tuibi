# 推币机的狂欢（COIN CARNIVAL）

> **手机竖屏 · 3D 混合街机增量大亨（Incremental Tycoon） · 推币物理 × 全球富豪榜 × 5~8 小时节奏**
> 基于 UrhoX（Lua 5.4 + `urhox-libs/UI` + UrhoX 3D 机台 + NanoVG 屏幕空间特效 + 零 GC 对象池 2.5D 物理）打造。

---

## 核心特色与玩法

1. **真机开屏即永动推币 · 3D/2D 无缝双模舞台**：
   - 自动发射炮口与往复斜口幸运门同周期摆动，下方 2.5D 梯形推台与侧漏缝实时挤推，**120 枚对象池上限**预留 50 槽给高频率手点与币雨。
   - **长按推台狂暴连发**：手点/长按发射金边强化币，享受持续推落快感；3D 模式支持镜头冲击、彩虹跑马灯、事件点光闪烁与 1:1 币槽平滑旋转。
2. **现金只涨不花 · 技能点 SP 驱动全部养成**：
   - 玩家赚取的现金与总身价**只涨不扣**，专心用于从 **全球第 8,000,000,000 名起点** 依次冲破 22 档匿名阶层与 63 位 **全球前 1,000 强真实富豪（直至 No.1 马斯克 ¥6,041,000,000,000）**！
   - 全部 8 项机台改造、22 枚渐进币种（支持自选 **6 枚常驻发射池** + 30% 前期功能币抽取）、12 项黑科技均只消耗累计身价达标与排名超越发放的 **技能点 SP**。
   - **方案 A 敲钟上市**：达标敲钟领传奇声望股与赠送技能点，绝不清空财富、机台与已解币种；登顶全球第 1 后解锁 **二周目星际飞升（Galactic Era）**！
3. **稀缺高燃爆发 · 幸运三连 + 冷却狂欢 + 波次连击**：
   - 过幸运门激活 3 轴幸运三连机（9 秒限流、队列上限 2 轮，1.5×~100× 限时爆发与币雨/⚡/45× 金库巨币，低奖不替高倍续命）。
   - **狂欢时刻（Fever）**：狂欢槽充能速率保护 + 结束后 **28 秒冷静冷却**，让每次狂欢爆发与 15 秒 **波次连击结算** 都极具节奏张力。
4. **JP 大奖池 · 酣畅淋漓的那一瞬间**（参考日式推币机 JP）：
   - **养分**：每笔推币收入抽 10% 悄悄存进 JP 奖池，侧漏掉的币 100% 流进奖池，三连没中也往里塞一点；机台前沿下方的 **JP 宝藏舱** 实时显示 GRAND 奖池与养分飘字。
   - **九宫格老虎机**：过幸运门转 3×3 九宫格（5 条中奖线），开出 **JP 宝箱** 点亮 JP 灯；7 盏全亮或 3 宝箱连线进入 **JP CHANCE**（距上次 JP 越久宝箱越容易出，差 1 灯时第三列拖长听牌）。
   - **JP CHANCE**：九宫格外圈 8 格跑灯抽奖 MINI / MAJOR / GRAND / NEXT（NEXT = 倍数 +1 再抽一轮，最多 ×3）；GRAND 一次带走整个奖池（跨多轮滚雪球）。
   - **倾泻**：奖金立刻到账 + 全屏巨额数字滚动 + 最高阶币瀑布砸向推台（GRAND 附送狂欢），随后弹窗可 **看广告再领一份（×2）**。
5. **节制商业化激励 + 双端可靠存档**：
   - 4 项常驻福利激励广告位（×3 印钞冷却 20 分钟上限 300s、超级狂欢、2 枚 45× 金库巨币、风投空投暴富 45 秒基准产值）+ 8 小时离线收益 + 双端本地/云端防覆盖存档。

---

## 模块结构

| 模块 | 职责说明 |
|---|---|
| [`scripts/main.lua`](scripts/main.lua) | 入口 (`Start` / `HandleUpdate` / `SetGamePaused` / `Stop`)，音效与 BGM 节流联动、3 秒急购写盘防抖 |
| [`scripts/game/Config.lua`](scripts/game/Config.lua) | 全局数值：120 池物理配置、8 机台改造、22 币阶梯与进化配方、12 黑科技、12 轮 IPO、幸运三连、广告位 |
| [`scripts/game/Billionaires.lua`](scripts/game/Billionaires.lua) | 80 亿名起点 → 22 档匿名阶层 → 63 位前 1000 强真实富豪榜与实时排名曲线 |
| [`scripts/game/Tycoon.lua`](scripts/game/Tycoon.lua) | 增量核心（浮点财富防 2⁶³ 溢出、9 秒限流幸运三连、28 秒冷却狂欢、波次连击、6 常驻发射池、5 分钟去噪长期 CPS、星际飞升） |
| [`scripts/game/Physics.lua`](scripts/game/Physics.lua) | 零 GC 空间哈希 2.5D 物理（3 迭代早退分离、`crowdBoost`、`magLip` 磁吸、滞留防卡死、11 颗倍增金钉） |
| [`scripts/game/Machine3D.lua`](scripts/game/Machine3D.lua) | UrhoX 3D 推币机台（1:1 币槽映射、AlphaMask 探针、四元数缓存、低端机脏阈值节流） |
| [`scripts/game/JackpotPanel.lua`](scripts/game/JackpotPanel.lua) | JP 宝藏舱：九宫格老虎机 / JP 奖池与 7 盏 JP 灯 / JP CHANCE 跑灯抽奖盘 / 全屏倾泻演出 |
| [`scripts/game/Stage.lua`](scripts/game/Stage.lua) | NanoVG 顶棚总倍率牌、3 轴幸运三连、带冷却倒计时的狂欢管、手点金环标注 |
| [`scripts/game/Fx.lua`](scripts/game/Fx.lua) | SoA 零 GC 特效池（近邻合并飘字、波次连击印章、飞币/倍率令牌、`SetQuality(0.5)` 低画质） |
| [`scripts/game/JuiceWidgets.lua`](scripts/game/JuiceWidgets.lua) | 滚动现金计数器 `CashCounter`（飞币砸击反馈）+ 顶层 `FxLayer` |
| [`scripts/game/TycoonHud.lua`](scripts/game/TycoonHud.lua) | 顶部双行状态与榜条 + 5 底部红点弹窗（机台/币种常驻/科技/上市飞升/福利）+ 前1000名榜 + 超越炫耀卡片 |
| [`scripts/game/Number.lua`](scripts/game/Number.lua) | 12 级中文大数字格式化（万..极、进位预舍入、`H:MM:SS` 时钟、`NaN`/`∞` 显式告警） |
| [`scripts/game/SaveManager.lua`](scripts/game/SaveManager.lua) | 原子本地存档 + 云端 3 键分包 + 换设备云读失败防覆盖保护 |

---

## 内置兑换码

在「设置」页面输入即可领取（不区分大小写，每人每档限领 1 次）：

| 兑换码 | 奖励内容 |
|---|---|
| `RICH2026` | 当前基准产值现金礼包 + 5 传奇股 + 启动资金 |
| `CARNIVAL2026` | 满槽超级狂欢 + 限时 ×3 印钞 + 最高阶币雨 |
| `COIN888` | 8 传奇股 + 8 枚高阶硬币空投 |

---

## 本地测试命令（`lupa` / Lua 5.4）

> 以下命令仅在本地环境跑通单测、渲染冒烟、3600 帧压测与 10 小时宏观数值校准：

```powershell
$PY = "C:\Users\Administrator\.taptap-maker\lua-lsp-venv\Scripts\python.exe"
& $PY "c:\Users\Administrator\Desktop\推币机的狂欢\tests\run_lua.py" "c:\Users\Administrator\Desktop\推币机的狂欢\tests\test_core.lua"
& $PY "c:\Users\Administrator\Desktop\推币机的狂欢\tests\run_lua.py" "c:\Users\Administrator\Desktop\推币机的狂欢\tests\test_render.lua"
& $PY "c:\Users\Administrator\Desktop\推币机的狂欢\tests\run_lua.py" "c:\Users\Administrator\Desktop\推币机的狂欢\tests\stress_perf.lua"
& $PY "c:\Users\Administrator\Desktop\推币机的狂欢\tests\run_lua.py" "c:\Users\Administrator\Desktop\推币机的狂欢\tests\sim_tycoon.lua"
```
