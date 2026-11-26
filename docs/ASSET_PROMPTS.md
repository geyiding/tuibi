# 《推币机的狂欢（COIN CARNIVAL）》美术替换与宣传素材生成提示词包

> 本文档严格对齐项目代码（[`scripts/game/Skin.lua`](../scripts/game/Skin.lua) 与 [`scripts/game/Config.lua`](../scripts/game/Config.lua)）及 `minigame-ui-spec` 规范编写。
> 现阶段游戏内置 **100% 程序化 NanoVG 高对比矢量渲染**，无需任何外部图片即可直接游玩；当你准备替换为 AI 生成或手绘的成品贴图时，按下方 **1 对 1 路径与规范** 放入 `assets/image/`，游戏即可自动热切换！

---

## 一、全游戏统一视觉圣经（Style Bible）

为保证所有自行生成的 UI 框、硬币、遗物、Boss 与宣传图放在同一竖屏画面里完全融洽，所有提示词共享以下统一风格锚点：

- **艺术流派**：**2.5D 霓虹街机潮酷波普风（2.5D Neon Arcade Pop-Art / Toy-Glossy Cyber Arcade）** —— 具有厚实糖果釉质反光、清晰金属倒角（Bevel）与浓郁霓虹灯管辉光，介于高级桌游筹码与赛博游艺机台之间。
- **固定视角与光影**：统一 **45° 微俯视斜顶光 + 边缘冷青/品红双色背光（Rim Light）**，所有硬币、遗物具有轻微厚度侧壁，阴影向正下方微偏坠落。
- **线稿与描边**：**厚实深蓝黑外描边（`#090B16`，2–3px 视觉权重）**，确保手机小屏高密度同屏 100+ 枚硬币时轮廓清晰不粘连、不刺眼。
- **官方核心调色盘**（提取自 `Skin.lua`）：
  - 深空底色 Deep Navy：`#0A0C1A` / `#141830`
  - 荧光青 Neon Cyan：`#38E0FF`
  - 霓虹品红 Neon Magenta：`#FF48B2`
  - 熔金橙 Molten Gold：`#FFD240`
  - 电光紫 Cyber Purple：`#A672FF`
  - 翡翠绿 Emerald Green：`#4AE88E`
  - 烈焰红 Crimson Alert：`#FF5260`
- **零代码热替换指南**：
  1. **硬币 / 遗物 / 机台 / Boss / 事件图**：按第二章表格路径直接将透明底 PNG（背景/插画除外）保存到 `assets/image/...`。[`Skin.ProbeAutoAssets()`](../scripts/game/Skin.lua#L33-L59) 会在启动时通过 `cache:Exists(path)` 自动探测并覆盖矢量图。
  2. **UI 九宫格框（Panel/Button/Card 等）**：放入 `assets/image/ui/*.png` 后，在 `Skin.lua` 顶部的 `Skin.TEXTURES` 表中登记路径与四边留白切片即可，例：
     ```lua
     Skin.TEXTURES.panel = { image = "image/ui/panel.png", slice = { 16, 16, 16, 16 } }
     Skin.TEXTURES.button = { image = "image/ui/button.png", slice = { 14, 14, 18, 14 } }
     ```
  3. 放完图片后在 TapTap Maker 刷新/生成 `.meta` 即可生效。

---

## 二、游戏内 1 对 1 贴图替换清单与 AI 提示词

### 2.1 UI 九宫格框与底板（`assets/image/ui/`，需配合 `Skin.TEXTURES` 登记）

| 资产键名 | 文件路径 | 建议尺寸 & 九宫格切片 (`{t,r,b,l}`) | 透明/背景要求 | 英文提示词 (EN Prompt) | 中文说明 |
|---|---|---|---|---|---|
| `panel` | `assets/image/ui/panel.png` | 256×256, `slice={24,24,24,24}` | 透明外圆角底 | `2.5D stylized neon arcade UI dialog panel frame, deep navy rounded rectangular body #141830 with thick glowing cyan bevel border #38E0FF and corner metallic rivets, clean empty center for nine-slice UI scaling, dark outline, crisp vector-paint hybrid game UI asset, transparent background, no text` | 深蓝圆角霓虹青描边弹窗大底框，四角铆钉，中间干净可拉伸 |
| `card` | `assets/image/ui/card.png` | 192×192, `slice={18,18,18,18}` | 透明外圆角底 | `Stylized cyber arcade UI item card container, dark indigo frosted inner panel #1C2242, crisp beveled border with subtle purple-cyan gradient glow, slight bottom 3D drop shadow lip, clean empty center for nine-slice, no text, transparent background` | 商店/三选一通用卡片框，深靛蓝微凸质感 |
| `slot` | `assets/image/ui/slot.png` | 128×128, `slice={14,14,14,14}` | 透明外圆角底 | `Small square beveled neon game inventory slot frame, recessed dark navy socket #0E1022 with bright cyan-silver inner rim, subtle inner shadow, nine-slice friendly empty middle, game UI asset, no text, transparent background` | 格子/徽章内嵌小槽位（投币仓、图鉴格子用） |
| `button` | `assets/image/ui/button.png` | 256×96, `slice={14,18,20,18}` | 透明外圆角底 | `Glossy 3D chunky arcade pill button UI sprite, vibrant golden-amber gradient face #FFD240 to #E88E18 with thick darker bottom bevel lip and bright top specular shine highlight, crisp dark outline, clean nine-slice stretchable center, no text, transparent background` | 立体厚底高光街机主按钮底图（金橙主按钮风格） |
| `plate` | `assets/image/ui/plate.png` | 256×96, `slice={10,12,14,12}` | 不透明底条 | `Horizontal top HUD bar header plate for cyber coin-pusher game, sleek dark metallic slate gradient with glowing neon cyan bottom trim stripe, clean top edge, tileable horizontal middle, no text` | 顶部状态栏金属底条，底边带霓虹青亮条 |
| `cloth` | `assets/image/ui/cloth.png` | 256×96, `slice={14,12,10,12}` | 不透明底条 | `Bottom arcade control dock bar plate, deep navy brushed metal surface with glowing neon magenta top accent trim #FF48B2, clean horizontal center for UI stretch, no text` | 底部拇指操作台金属底座，顶边带霓虹粉光条 |
| `banner` | `assets/image/ui/banner.png` | 256×80, `slice={12,24,14,24}` | 透明外圆角底 | `Bold stylized arcade ribbon banner frame, bright electric cyan plate with crisp white inner trim and chunky bottom 3D edge, clean center for text overlay, game UI asset, transparent background, no text` | 狂欢/过关弹窗标题飘带横幅 |

---

### 2.2 机台背景、推板与机关（`assets/image/machine/`，`Skin.ProbeAutoAssets` 自动加载）

| 资产键名 | 文件路径 | 建议尺寸 | 透明要求 | 英文提示词 (EN Prompt) | 中文说明 |
|---|---|---|---|---|---|
| `backdrop_act1` | `assets/image/machine/backdrop_act1.png` | 512×480 | 不透明 | `Vertical coin-pusher arcade machine backboard texture, Act 1 Neon Arcade Hall theme, deep purple-navy geometric cyber grid #161234 with glowing cyan and magenta neon tube patterns at edges, dark uncluttered center so falling coins pop clearly, 2.5D stylized game art, no text` | 第1幕「霓虹游艺厅」上部落币槽深紫赛博背景板 |
| `backdrop_act2` | `assets/image/machine/backdrop_act2.png` | 512×480 | 不透明 | `Vertical coin-pusher arcade machine backboard texture, Act 2 Molten Gold Furnace theme, dark bronze-obsidian industrial furnace plates with glowing amber-orange molten pipes at sides, clean dark central contrast zone for coin visibility, stylized arcade art, no text` | 第2幕「黄金熔炉」铜铁熔炉工业风背板 |
| `backdrop_act3` | `assets/image/machine/backdrop_act3.png` | 512×480 | 不透明 | `Vertical coin-pusher arcade machine backboard texture, Act 3 Cyber Vault theme, obsidian vault steel doors with electric purple and radiant gold laser lock lines on perimeter, clean low-noise center, stylized arcade game background, no text` | 第3幕「赛博金库」紫金机密金库背板 |
| `pusher_bar` | `assets/image/machine/pusher_bar.png` | 512×128 | 透明边缘 | `Top-down 2.5D isometric arcade coin-pusher sliding shelf bar, metallic purple-slate top platform with thick glowing neon magenta front pushing lip #FF48B2 and brushed steel hazard stripes, game sprite asset, transparent background, no text` | 梯形往复推台本体与品红荧光推进前唇 |
| `gate_badge` | `assets/image/machine/gate_badge.png` | 160×64 | 透明底 | `Futuristic neon arcade jackpot gate bracket badge, twin glowing magenta bumpers framing a bright gold energy beam chute in the center, 2.5D glossy game sprite, isolated on transparent background, no text` | 上部左右往复中奖门机关贴图 |

---

### 2.3 三幕守关 Boss 立绘（`assets/image/boss/`，`Skin.ProbeAutoAssets` 自动加载）

| Boss ID | 文件路径 | 建议尺寸 | 透明要求 | 英文提示词 (EN Prompt) | 中文说明 |
|---|---|---|---|---|---|
| `gatekeeper` | `assets/image/boss/boss_gatekeeper.png` | 256×256 | 透明背景 | `2.5D stylized cartoon arcade boss emblem: The Iron Gatekeeper, imposing armored cyber-casino robot torso wearing a neon gold crown and heavy laser-barrier gauntlets, glowing cyan visor eyes, bold dark ink outline, centered game portrait on transparent background, no text` | 第1幕 Boss「铁闸庄家」：头戴金冠的铁闸机甲庄家 |
| `furnace` | `assets/image/boss/boss_furnace.png` | 256×256 | 透明背景 | `2.5D stylized arcade boss icon: Molten Furnace Wheel, giant heavy steampunk-cyber rotary foundry core bursting with glowing orange-gold magma gears and slag vents, bold dark outline, high contrast glossy game art on transparent background, no text` | 第2幕 Boss「熔金巨轮」：喷吐熔岩金渣的重型转轮核心 |
| `vaultbeast` | `assets/image/boss/boss_vaultbeast.png` | 256×256 | 透明背景 | `2.5D stylized arcade final boss mascot: Cyber Vault Leviathan, menacing armored purple-gold mechanical dragon-mimic chest with glowing vault dial jaw and golden teeth, neon cyan energy veins, bold dark ink outline, transparent background, no text` | 第3幕最终 Boss「终极吞金兽」：金库装甲机械噬金巨兽 |

---

### 2.4 全套 25 种硬币正面精灵图（`assets/image/coins/coin_<id>.png`，`256×256` 正圆透明底 PNG）

> **通用后缀锚点（制作每枚币时拼在 prompt 末尾）**：`top-down slightly angled 2.5D glossy arcade game coin token, chunky beveled metallic rim, clean dark outline #090B16, vivid highlights, centered isolated icon on transparent background, no tiny unreadable text`。

#### 基础/稀有/传说卡池（16 种）

| 币种 ID | 文件路径 | 中文名 / 家族 | 英文提示词 (EN Prompt) | 中文画面要点 |
|---|---|---|---|---|
| `gold` | `assets/image/coins/coin_gold.png` | 标准金币 (财富) | `Classic bright radiant gold arcade coin #F8C430, raised vertical bar emblem in center, chunky golden bevel rim, shiny specular glint + [通用后缀]` | 亮金色高光经典街机代币，中央竖条浮雕 |
| `emerald` | `assets/image/coins/coin_emerald.png` | 幸运翡翠 (狂欢) | `Translucent glossy emerald-green jade coin #42DA8A with a glowing bright mint 4-leaf clover relief embedded in the center + [通用后缀]` | 通透翡翠绿宝石币，内嵌幸运四叶草 |
| `split` | `assets/image/coins/coin_split.png` | 分裂子母 (倾泻) | `Aqua-teal futuristic alloy coin #60E0BC with twin glowing silver-blue twin dots and geometric split seam line across the middle + [通用后缀]` | 水青色子母双核代币，带可裂变对分纹 |
| `heavy` | `assets/image/coins/coin_heavy.png` | 重锤铁币 (聚能) | `Oversized thick forged gunmetal-steel iron weight coin #8898BA, heavy industrial rivets around edge and bold anvil mark in center + [通用后缀]` | 厚重锻铁铆钉重型币，中间铁砧压痕 |
| `thunder` | `assets/image/coins/coin_thunder.png` | 霹雳电币 (连锁) | `Electric sky-blue neon plasma coin #4CC6FF, sharp glowing white-cyan lightning bolt emblem crackle inside glass center + [通用后缀]` | 亮天蓝等离子闪电图标硬币 |
| `bomb` | `assets/image/coins/coin_bomb.png` | 定时炸弹 (爆破) | `Crimson-orange danger ordinance coin #F46048, stylized cartoon round bomb sphere motif inside with a tiny sparking golden fuse glint at upper right + [通用后缀]` | 炽红橙爆弹币，右上带闪亮引线火星 |
| `spring` | `assets/image/coins/coin_spring.png` | 高弹霓虹 (倾泻) | `Bouncy neon bubblegum-pink rubberized core coin #FF74C4 surrounded by glossy chrome rim and glowing cyan bounce ring + [通用后缀]` | 高弹霓虹粉胶芯镀铬弹力币 |
| `magnet` | `assets/image/coins/coin_magnet.png` | 磁石吸金 (聚能) | `Deep violet-amethyst magnetic core coin #A674FF featuring a bold glowing red-and-silver horseshoe magnet icon on the face + [通用后缀]` | 亮紫色磁芯代币，正面大号 U 形磁铁徽章 |
| `ruby` | `assets/image/coins/coin_ruby.png` | 红宝石倍率 (财富) | `Luxurious faceted crimson ruby coin #EC3862 set in ornate gold bevel bezel, jewel-cut diamond facets shining in center + [通用后缀]` | 镶金边切割红宝石代币 |
| `neon` | `assets/image/coins/coin_neon.png` | 狂热霓虹 (狂欢) | `Ultra-bright neon hot-pink disc coin #FF44DC with electric cyan outer glow rim and glowing 5-point party star emblem + [通用后缀]` | 荧光紫粉+电青双色狂欢星币 |
| `frost` | `assets/image/coins/coin_frost.png` | 冰晶棱币 (聚能) | `Icy translucent cyan sapphire coin #76EEFF, sharp geometric 6-point snowflake crystal inside frosted glass bevel + [通用后缀]` | 晶莹冰棱雪花水晶币 |
| `ghost` | `assets/image/coins/coin_ghost.png` | 幽灵穿影 (连锁) | `Semi-translucent ethereal ice-lavender ghost coin #AED2FF with cute mischievous neon spectral flame emblem glowing softly + [通用后缀]` | 半透明幽蓝灵能穿墙幻影币 |
| `jackpot7` | `assets/image/coins/coin_jackpot7.png` | 777轮盘币 (狂欢) | `Legendary gilded Vegas casino token #FFD72E, glowing neon pink-red rim ring with ornate golden lucky 7 emblem glowing inside + [通用后缀]` | 传说尊金轮盘币，红粉灯圈与金辉 7 图腾 |
| `blackhole` | `assets/image/coins/coin_blackhole.png` | 黑洞奇点 (聚能) | `Legendary cosmic singularity coin, pitch-dark obsidian void core surrounded by swirling neon violet-magenta accretion swirl and rim #9C56FF + [通用后缀]` | 深紫黑洞漩涡吸积盘奇点币 |
| `giant` | `assets/image/coins/coin_giant.png` | 黄金巨人 (财富) | `Massive thick heavy royal gold medallion coin #FFB224 with a bold golden king crown relief and double layered chamfered rim + [通用后缀]` | 特大号厚切皇家金冠巨型币 |
| `nuke` | `assets/image/coins/coin_nuke.png` | 核能烈焰 (爆破) | `Legendary fiery molten magma core coin #FF4C2A encased in dark titanium ring with glowing radioactive trefoil flame icon + [通用后缀]` | 黑钛框裹烈焰辐射核心核爆币 |

#### 内部衍生与 Boss 专用币（3 种）

| 币种 ID | 文件路径 | 名称 / 用途 | 英文提示词 (EN Prompt) | 中文画面要点 |
|---|---|---|---|---|
| `mini` | `assets/image/coins/coin_mini.png` | 银分身 (分裂小银币) | `Sleek polished chrome-silver mini arcade coin #CADCF2, simple raised center dot, bright icy highlights + [通用后缀]` | 轻巧高反光镀铬小银币 |
| `slag` | `assets/image/coins/coin_slag.png` | 熔渣废币 (Boss2 空投) | `Heavy rough volcanic dark iron slag coin #6A5E5C with glowing molten orange magma cracks oozing across the scarred face + [通用后缀]` | 开裂暗铁裹炽橙熔岩缝 |
| `vault` | `assets/image/coins/coin_vault.png` | 装甲金库币 (Boss3 宝箱币) | `Heavy armored golden cyber bank vault door coin #F0CE62 with neon cyan locking spokes and steel armored rim + [通用后缀]` | 重装甲黄金金库密码锁盘币 |

#### 融合进化传说币（6 种）

| 币种 ID | 文件路径 | 名称 / 配方 | 英文提示词 (EN Prompt) | 中文画面要点 |
|---|---|---|---|---|
| `midas` | `assets/image/coins/coin_midas.png` | 点金圣王 (`金币+红宝`) | `Legendary divine solar gold coin #FFE03E with radiant sunlit halo aura, ornate golden royal sun-crown gem core, ultra shiny jewel finish + [通用后缀]` | 圣金光环皇冠宝石太阳币 |
| `thor` | `assets/image/coins/coin_thor.png` | 雷神之锤 (`重锤+霹雳`) | `Legendary electrified forged storm coin #62E4FF, heavy gold-trimmed rim framing a radiant stylized cyber thunder hammer + [通用后缀]` | 雷霆蓝金重装战锤神币 |
| `supernova` | `assets/image/coins/coin_supernova.png` | 超新星爆 (`炸弹+霓虹`) | `Legendary cosmic starburst coin #FF5CAE, blinding white-gold fusion core radiating magenta and solar orange shockwaves + [通用后缀]` | 粉紫耀金恒星爆发核心币 |
| `hydra` | `assets/image/coins/coin_hydra.png` | 无限分身 (`分裂+弹跳`) | `Legendary bio-cyber emerald mint coin #52F8AE with interlocking three-way infinity spiral arrows and glowing aqua crystal core + [通用后缀]` | 翡翠荧光三向无限分裂晶核币 |
| `singularity` | `assets/image/coins/coin_singularity.png` | 奇点涡轮 (`黑洞+磁石`) | `Legendary deep cosmic ultraviolet turbine coin #964AFF with glowing cyan magnetic blades spinning around a dark void center + [通用后缀]` | 紫电磁刃涡轮环绕虚空奇点币 |
| `carnival` | `assets/image/coins/coin_carnival.png` | 狂欢大满贯 (`777+翡翠`) | `Ultimate prismatic rainbow-gold grand jackpot arcade coin #FFCC40, neon cyan-magenta-gold aurora glaze with radiant 8-point firework star + [通用后缀]` | 幻彩炫金+极光粉青烟花大满贯终极币 |

---

### 2.5 全套 20 种遗物/改装件图标（`assets/image/relics/relic_<id>.png`，`192×192` 透明底 PNG）

> **统一后缀**：`, chunky stylized 2.5D neon arcade game gadget icon, thick dark ink outline, glossy specular finish, centered isolated object on transparent background, no text`

| 遗物 ID | 路径 (`assets/image/relics/...`) | 中文名 | 核心英文画面描述 (拼接统一后缀) |
|---|---|---|---|
| `rail_guard` | `relic_rail_guard.png` | 合金护栏 | `Glowing neon cyan metallic arcade bumper shield rail with gold corner bolts` |
| `turbo_pusher` | `relic_turbo_pusher.png` | 涡轮活塞 | `Chrome hydraulic piston spring coil glowing bright emerald-green kinetic aura` |
| `golden_pegs` | `relic_golden_pegs.png` | 黄金倍增钉 | `Trio of shiny golden pachinko bumper pins radiating starlight sparks` |
| `wide_gate` | `relic_wide_gate.png` | 宽口中奖门 | `Miniature neon cyan-magenta arcade prize archway gate glowing open` |
| `metronome` | `relic_metronome.png` | 连击节拍器 | `Futuristic glowing cyber metronome with cyan lightning tempo needle` |
| `medkit` | `relic_medkit.png` | 救急芯片 | `Cute rounded crimson neon cybernetic heart microchip with white cross highlight` |
| `big_pouch` | `relic_big_pouch.png` | 大额币袋 | `Chunky indigo leather arcade coin pouch overflowing with shiny gold coins` |
| `bankbook` | `relic_bankbook.png` | 复利金库 | `Ornate compact golden cyber piggy-bank vault box locked with cyan dial` |
| `crit_seal` | `relic_crit_seal.png` | 暴击印章 | `Fiery crimson-gold wax & metal wax seal stamp shaped like an explosion star` |
| `fever_amp` | `relic_fever_amp.png` | 狂欢扩音器 | `Retro-futuristic neon magenta-gold arcade megaphone speaker blasting sound rings` |
| `double_barrel` | `relic_double_barrel.png` | 双发枪管 | `Twin-bore gleaming cyan cybernetic coin launcher barrel nozzle` |
| `mag_lip` | `relic_mag_lip.png` | 磁力前沿 | `Glowing violet industrial electromagnet bar attracting tiny golden sparks` |
| `powder_keg` | `relic_powder_keg.png` | 超级火药 | `Chunky stylized red-gold hazard dynamite keg with neon warning stripe` |
| `tesla_coil` | `relic_tesla_coil.png` | 高压线圈 | `Copper and neon electric-blue Tesla coil tower crackling bright arcs at top sphere` |
| `clover` | `relic_clover.png` | 幸运四叶草 | `Radiant emerald-crystal four-leaf clover brooch framed in bright gold wire` |
| `recycler` | `relic_recycler.png` | 回收磁爪 | `Cute cybernetic arcade claw-machine pincer grabbing a shiny gold coin` |
| `vip_card` | `relic_vip_card.png` | 黄金会员卡 | `Tilted luxury black-and-gold cyber VIP membership keycard with glowing crown icon` |
| `overclock` | `relic_overclock.png` | 超频散热 | `Dual-fan neon gold-and-crimson cyber GPU cooling heatsink unit with glowing heatpipes` |
| `first_surge` | `relic_first_surge.png` | 首冲引擎 | `Glowing orange-cyan rocket turbocharger engine core brimming with ignition flame` |
| `prism` | `relic_prism.png` | 霓虹棱镜 | `Floating cut rainbow diamond crystal prism splitting cyan magenta gold light beams` |

---

### 2.6 全套 6 个奇遇事件插画（`assets/image/events/event_<id>.png`，`512×240` 横版微暗圆角卡图）

| 事件 ID | 路径 (`assets/image/events/...`) | 中文标题 | 英文提示词 (EN Prompt) |
|---|---|---|---|
| `gold_altar` | `event_gold_altar.png` | 黄金祭坛 | `2.5D stylized cyber arcade illustration: ancient glowing golden slot-machine altar inside a neon purple temple, dual glowing crimson and gold coin chutes emitting mystical light beams, bold ink style, no text` |
| `scrap_smith` | `event_scrap_smith.png` | 机台改造匠 | `2.5D stylized arcade illustration: friendly cybernetic goblin-mechanic booth with glowing cyan welding goggles forging and polishing radiant coins on a neon anvil workbench, cozy high-contrast lighting, no text` |
| `lucky_wheel` | `event_lucky_wheel.png` | 午夜赌局 | `2.5D stylized arcade illustration: extravagant glowing neon fortune roulette wheel spinning in midnight velvet spotlight with floating emerald and gold chips around it, dramatic pop colors, no text` |
| `neon_spring` | `event_neon_spring.png` | 狂欢充能站 | `2.5D stylized cyber illustration: vertical glowing magenta-and-violet plasma energy battery fountain bubbling with golden star sparks inside an arcade repair bay, no text` |
| `magnet_trap` | `event_magnet_trap.png` | 废料清道夫 | `2.5D stylized arcade illustration: giant overhead industrial electromagnetic crane sweeping old dark iron coins into a glowing recycling vortex while bright gems remain, no text` |
| `vault_crack` | `event_vault_crack.png` | 加密金库门 | `2.5D stylized arcade illustration: gleaming cyber armored gold bank vault door cracked slightly open with bright neon cyan security lasers and golden light pouring out, no text` |

---

## 三、宣发素材三件套 AI 提示词（Marketing 3-Piece Package）

> 已严格按 `minigame-ui-spec/references/asset-prompts.md` 规范编写：**主图标含 3×3 九宫格分工、16:9 宣传图强制预留左上标题安全区、16:9 15 秒视频配齐四幕时间轴脚本**。

---

### 3.1 游戏头像 / 主图标（1:1 比例 · 3×3 九宫格多帧动感展示）

- **比例与用途**：`1:1`（推荐出图 `1024×1024` 或 `2048×2048`，可整体当商店 Icon 灵感矩阵，也可按 3×3 等分切出 9 枚独立高精度展示头像）。
- **设计思路**：9 个方格分别呈现《推币机的狂欢》从“普通代币 → 弹珠钉阵 → 中奖门 → 狂欢瀑布 → 闪电炸弹暴击 → 终极 777 大满贯”的不同高光切面，画面干净**零文字、零 UI 框**。

| 九宫格坐标 | 格内核心视觉主体（零文字） | 主色调 |
|---|---|---|
| `[1,1]` 左上 | 单枚特写经典亮金币在蓝色霓虹光晕中旋转坠落 | 金 + 青 |
| `[1,2]` 上中 | 亮银/天蓝霹雳电币撞击发光弹珠钉溅起电弧 | 蓝 + 紫 |
| `[1,3]` 右上 | 红宝石与黄金巨人巨币交叠闪烁宝石切面光 | 红 + 金 |
| `[2,1]` 左中 | 粉紫高弹霓虹币穿越品红发光中奖门触发星光喷涌 | 粉 + 金 |
| `[2,2]` 中心主格 | **核心皇冠主角图**：金库推台边缘百枚七彩硬币正被品红推板倾泻推落，777大满贯币耀眼腾空 | 金 + 青 + 粉 |
| `[2,3]` 右中 | 定时炸弹与核能烈焰币引爆橘红冲击波掀飞周遭代币 | 橙红 + 金 |
| `[3,1]` 左下 | 翡翠幸运币与四叶草泛出柔和青绿极光能量环 | 翡翠绿 |
| `[3,2]` 下中 | 黑洞奇点紫旋涡吸引数枚金币环绕轨道飞旋 | 深紫 + 青 |
| `[3,3]` 右下 | 满屏黄金金币雨如瀑布般倾泻入深蓝霓虹游艺箱底槽 | 金灿灿 |

- **完整英文 Prompt（1:1 九宫格）**：
```text
A tight 3x3 square grid collage divided cleanly by thin dark border lines into 9 equal panels, showcasing 9 dynamic close-up icons and highlight moments of a stylized 2.5D Neon Arcade Coin-Pusher roguelike game, glossy toy-like rendering, bold dark outlines, deep midnight navy backdrops (#0A0C1A), NO text, NO letters, NO UI frames:
Top-left: close-up radiant classic gold coin descending through cyan neon glow;
Top-center: electric sky-blue thunder coin striking glowing pachinko pins with crackling lightning arcs;
Top-right: faceted crimson ruby coin stacked against a massive crowned golden giant medallion;
Middle-left: hot-pink bouncy neon coin soaring through a glowing magenta jackpot gate arch;
Center focal panel: dramatic hero view of a neon cyber coin-pusher shelf overflowing with shimmering gold, emerald and rainbow 777 jackpot coins cascading off the edge pushed by a glowing magenta bar;
Middle-right: stylized cartoon orange bomb coin detonating a bright fiery shockwave scattering coins into the air;
Bottom-left: translucent emerald jade four-leaf clover coin glowing with mint aurora sparks;
Bottom-center: cosmic violet black-hole vortex coin pulling orbiting gold tokens in a neon spiral;
Bottom-right: explosive fountain waterfall of golden coins showering down into a neon blue arcade tray.
Consistent vibrant arcade lighting, ultra-crisp 2.5D stylized game icon quality.
```

- **完整中文参考 Prompt（便于即梦/可灵直接理解使用）**：
```text
严格均分 3x3 九宫格拼图展示，细暗线清晰隔开 9 个等大正方形画面，呈现 2.5D 霓虹街机风肉鸽推币游戏的 9 个核心代币与高光瞬间，潮酷厚涂硬边描边，高光琉璃玩具质感，深海午夜暗蓝底色，画面中严禁出现任何文字、数字、按钮或UI框：
[左上] 亮金色经典街机金币伴随荧光青尾迹落下；
[上中] 天蓝霹雳闪电币撞击霓虹弹珠钉迸发蓝色电弧；
[上右] 奢华红宝石币与皇家金冠巨币交叠闪耀；
[左中] 高弹荧光粉币穿过发光的品红中奖门激起星光；
[正中C位] 霓虹推币机台前沿爆发瀑布式金币潮，发光品红推板把海量金币与777幻彩大满贯币推落悬崖；
[右中] 卡通炸弹与烈焰核心币引爆耀眼冲击波炸飞金币；
[左下] 翡翠绿四叶草幸运币散发柔和极光绿环；
[下中] 紫色黑洞奇点漩涡硬币将周边金币吸入螺旋轨道；
[右下] 漫天黄金金币雨如金色瀑布倾泻进霓虹游艺槽。
整体光影色彩高度统一，饱和炫目。
```

---

### 3.2 16:9 横版宣传图（Key Art Banner · 严格预留标题安全区）

- **比例与用途**：`16:9`（建议 `1920×1080` 或 `2560×1440`），用于 TapTap 详情页头图、横版推广封面。
- **构图布局与安全区**：
  - **视觉重心偏右下 60%**：3/4 斜仰视/微俯视透视的巨型霓虹游艺推币机台从右侧拔地而起，机台前唇正在向画面中下部倾泻金色瀑布与各色元素代币（闪电、炸弹、翡翠、777 大满贯）。
  - **左上区（画面左上 35% 区域）预留简洁暗夜霓虹深空虚化留白**，供后期叠加游戏中文大标题《推币机的狂欢》及 Slogan，没有任何乱码文字！

- **完整英文 Prompt（16:9 Key Art）**：
```text
16:9 horizontal widescreen key art illustration for a 2.5D stylized Neon Arcade Roguelike Coin-Pusher game, ultra-vibrant pop-art toy-glossy lighting, bold crisp dark outlines.
Composition weighted heavily to the right and bottom-right: an angled heroic view of a towering futuristic cyber-arcade coin-pusher machine glowing with cyan #38E0FF and magenta #FF48B2 neon rails. Hundreds of glossy gold coins, emerald clover tokens, crackling blue lightning coins, fiery bomb coins, and a gleaming rainbow 777 jackpot centerpiece burst forward off the sliding neon pusher shelf like an unstoppable golden waterfall cascade, sending luminous sparkles and energy arcs spraying toward the camera.
Top-left corner composition rule: keep the upper-left 35% of the frame clean, spacious, deep dark midnight-blue cyber twilight sky (#0A0C1A) with only soft out-of-focus bokeh neon lights as a dedicated empty negative-space title safe zone.
Zero text, zero letters, zero logos, zero UI HUD elements anywhere in the artwork.
```

- **完整中文参考 Prompt（16:9 主视觉）**：
```text
16:9 横版高清游戏主视觉宣传插画，2.5D 霓虹街机潮酷波普风格，厚涂硬边深色描边与晶莹糖果高光质感。
构图重心置于画面右侧与右下方：大透视角度展示一座闪耀着荧光青与霓虹品红灯管的未来赛博推币机台，发光推板猛烈推出层层叠叠的金色硬币海啸，夹杂着闪电蓝币的跳跃电弧、爆炸火红币的冲击火花、翡翠幸运币以及悬浮在潮头最亮眼的幻彩777大满贯币，成百上千枚硬币正如黄金瀑布般向镜头前方倾泻爆发！
关键安全区约束：画面左上角 35% 区域必须保持干净深邃的暗夜藏青虚化霓虹散景留白，留作后期排版游戏主标题的安全空区，不要画满复杂前景物。
画面中绝对不要生成任何文字、字母、水印或游戏UI边框。
```

---

### 3.3 16:9 15 秒宣传视频生成提示词（Sora2 / Veo / Kling 通用脚本）

#### 完整连续英文视频 Prompt（16:9 · 15s）
```text
15-second continuous high-energy 16:9 stylized 2.5D neon arcade game showcase trailer, ultra-smooth 60fps camera work, glossy cyber-pop art style with deep midnight navy backdrop (#0A0C1A), electric cyan (#38E0FF), hot magenta (#FF48B2), and glowing gold (#FFD240) VFX, zero UI text overlays:
[0s-3s Opening Aim & Pin Drop] Dynamic vertical tilt down a sleek cyber coin-pusher arcade cabinet: a gleaming gold coin drops from the top chute, zigzags cleanly down glowing cyan and amber pachinko pegs emitting bright sparks, and threads dead-center through a sliding neon magenta jackpot gate archway.
[3s-7s Escalation & Elemental Chain Reaction] The camera glides lower toward the metallic pusher shelf packed wall-to-wall with shimmering coins; an electric blue thunder coin lands and arcs jagged cyan lightning chains across 6 neighboring coins while an orange bomb coin detonates a punchy warm shockwave pushing the front row to the brink.
[7s-12s Fever Climax Waterfall] The entire arcade cabinet borders flash brilliant gold-pink Fever mode; the glowing magenta pusher bar surges rapidly forward as a dazzling torrent of fifty golden and emerald coins pours from above like a waterfall, unleashing a colossal avalanche of glittering coins spilling nonstop off the front ledge in slow-motion bursts of golden light rays.
[12s-15s Hero Finale Freeze] The camera pulls back slightly with triumphant confetti sparks and rainbow aurora glow radiating around a gleaming central 777 mega-coin emerging over the overflowing vault tray, landing in a clean dramatic final hero hold with open dark bokeh room on the upper side for end-slate logo placement.
```

#### 四幕分镜节奏对照表（方便逐段拆镜微调）

| 时间轴 | 阶段名 | 镜头与主体动作 | 爽点视听反馈建议（配合本游戏音频/节奏） |
|---|---|---|---|
| `0s – 3s` | **摆动狙门开局** | 镜头跟随顶部金色代币落下，灵动穿梭青紫高亮钉阵，精准钻过滑动品红中奖门 | 清脆叮当音（`peg1`→`peg_mult`），过门刹那光环炸开（`gate_win`） |
| `3s – 7s` | **连锁元素引爆** | 镜头压低至满台硬币推台：霹雳电币炸出 5 段电弧、炸弹币引爆橘红震荡波 | 鼓点切入增强，闪电爆裂与重低音推浪（`zap` + `explode`） |
| `7s – 12s` | **Fever 狂欢瀑布** | 机台全框暴闪黄金霓虹，推板超频急进 + 天降海量金币雨，前沿整排币倾泻跌落 | 节奏瞬间拉满，黄金喷泉连响爆音（`fever` + `crit` + `drop` 连刷） |
| `12s – 15s` | **777 大满贯定格** | 拉远定格：幻彩 777 巨币领衔金币海啸，上方留出暗青散景霓虹留白 | 礼花大奖音效余韵（`jackpot` + `win`），后期加标题收尾 |
