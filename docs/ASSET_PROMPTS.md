# 《推币机的狂欢（COIN CARNIVAL）》全套拼图提示词 & 一键切图指南

> **极简工作流：不用生成 66 张零碎小图！只需生成下面 8 张拼图（7 张 `3×3` 九宫格 + 1 张 `1×3` Boss 横拼），一键全自动切分成全部 66 张游戏成品贴图！**
>
> **操作步骤（3 步零代码换肤）**：
> 1. **直接复制生成 8 张原图**：下文**每一块英文/中文提示词都已包含统一画风、纯白可抠背景/九宫格无框排版与禁字规则**，无需自己拼接任何前后缀，直接整段复制粘贴去生成，并按每节标出的文件名存入 `devtools/raw_sheets/`（如 `devtools/raw_sheets/sheet_01_coins_a.png`）。
> 2. **运行自动切图脚本**：脚本会自动按格切割、以四周边缘洪水填充安全抠掉白底（保留硬币高光不破损）、裁剪居中并缩放到游戏精确尺寸，输出到 `assets/image/...` 全部 66+ 个路径：
>    ```powershell
>    "C:\Users\Administrator\.taptap-maker\python\uv\cpython-3.12-windows-x86_64-none\python.exe" "devtools\slice_sheets.py"
>    ```
> 3. **生效与 UI 九宫格登记**：机台/Boss/硬币/遗物/事件（59 张）放图后在 TapTap Maker 刷新 `.meta` 即由 [`Skin.ProbeAutoAssets()`](../scripts/game/Skin.lua#L33-L59) **零代码自动加载**；另外 7 张 UI 底框只需在 [`Skin.lua`](../scripts/game/Skin.lua#L17) 的 `Skin.TEXTURES` 写 7 行映射表（详见 2.6 节）即可启用！

---

## 一、统一视觉风格锚点（已全部内嵌到下方每段提示词中，仅供审图对照）

- **统一画风**：**2.5D 霓虹街机潮酷波普风（`2.5D stylized neon arcade pop-art`）** —— 45° 微俯视斜顶光 + 霓虹青/品红边缘光，厚实深蓝黑外描边（`#090B16`）配琉璃糖果光泽质感。
- **背景分工铁律**：
  - **图集 1~6 & 图集 8（需要抠图透明底的硬币/遗物/UI/Boss）**：全部强制出 **纯白无杂质背景（`solid pure white #FFFFFF background`）** 且格子之间留宽白边、不画网格黑线，避免切图误伤半透明发光与硬币高光。
  - **图集 7（机台背板 + 奇遇事件插画）**：全部为暗夜霓虹不透明画幅，无边框无白边，按比例中心裁剪铺满使用。

---

## 二、游戏内拼图集提示词（共 8 张，全部独立完整可直拷）

### 2.1 图集 1：9 枚基础代币九宫格 -> 保存为 `devtools/raw_sheets/sheet_01_coins_a.png`

- **出图比例 & 建议分辨率**：`1:1`（推荐 `2048×2048`）
- **切分对照（从左到右、从上到下，脚本切为 `256×256` 透明 PNG）**：

| 左 | 中 | 右 |
|---|---|---|
| `[1,1]` `coin_gold.png` (标准金币) | `[1,2]` `coin_emerald.png` (幸运翡翠) | `[1,3]` `coin_split.png` (分裂子母) |
| `[2,1]` `coin_heavy.png` (重锤铁币) | `[2,2]` `coin_thunder.png` (霹雳电币) | `[2,3]` `coin_bomb.png` (定时炸弹) |
| `[3,1]` `coin_spring.png` (高弹霓虹) | `[3,2]` `coin_magnet.png` (磁石吸金) | `[3,3]` `coin_ruby.png` (红宝石倍率) |

#### 一键复制英文 Prompt（图集 1 · 基础 9 币）
```text
Clean 3x3 grid sheet of 9 distinct game coin icons arranged neatly with generous empty space between every coin, NO grid lines, NO borders, NO dividers, isolated on a flat solid pure white #FFFFFF background (no ground cast shadow onto the white background). Consistent 2.5D stylized neon arcade pop-art style, top-down slightly angled glossy coin tokens with chunky beveled metallic rims, 45-degree specular highlights, subtle neon cyan/magenta rim glint, bold dark ink outlines #090B16, zero text, zero letters, zero watermark:
Row 1 Left: classic radiant gold arcade coin #F8C430 with a raised vertical bar emblem in center;
Row 1 Center: translucent glossy emerald-green jade coin #42DA8A with a glowing mint four-leaf clover emblem;
Row 1 Right: aqua-teal alloy coin #60E0BC with twin glowing silver-aqua dots and a geometric split seam across the middle;
Row 2 Left: oversized thick forged gunmetal-steel iron weight coin #8898BA with perimeter rivets and anvil emblem;
Row 2 Center: electric sky-blue plasma coin #4CC6FF with a sharp glowing white-cyan lightning bolt emblem inside glass;
Row 2 Right: crimson-orange danger ordinance coin #F46048 with a cartoon round bomb sphere motif and tiny golden spark fuse;
Row 3 Left: bouncy neon hot-pink rubberized core coin #FF74C4 framed in glossy chrome and cyan bounce glow ring;
Row 3 Center: deep violet magnetic core coin #A674FF featuring a glowing red-and-silver horseshoe magnet icon on the face;
Row 3 Right: luxurious faceted crimson ruby gemstone coin #EC3862 set inside an ornate golden beveled rim.
```

#### 一键复制中文 Prompt（图集 1 · 国内生图工具直出）
```text
严格 3x3 规整九宫格排列的 9 枚独立游戏代币图标素材表，格子之间保留充足留白，严禁画任何分割线或边框，纯白无杂质背景 #FFFFFF（不要在白底上投射阴影），画面无任何文字与字母。统一 2.5D 霓虹街机潮酷波普风格，微俯视斜角度厚金属倒角圆币，45度琉璃高光，外围一圈清晰厚实的深蓝黑描边 #090B16：
第一行左：亮金色标准街机金币，中央竖条浮雕；
第一行中：通透翡翠绿宝石硬币，中央发光四叶草浮雕；
第一行右：水青色合金硬币，表面有一对发光双圆点与对半裂变暗纹；
第二行左：厚重锻铁重锤硬币，外圈铆钉与中央铁砧徽记；
第二行中：电光天蓝等离子硬币，透明晶芯里闪耀白青色霹雳闪电；
第二行右：炽红橙炸弹硬币，正面圆球卡通炸弹带右上角小火花引线；
第三行左：高弹霓虹荧光粉胶芯镀铬弹力币，带荧光青弹力光环；
第三行中：深紫磁芯硬币，正面嵌红银双色 U 形马蹄磁铁徽章；
第三行右：金边镶嵌切割大红宝石硬币，多面宝石切光。
```

---

### 2.2 图集 2：9 枚进阶/传说/衍生代币九宫格 -> 保存为 `devtools/raw_sheets/sheet_02_coins_b.png`

- **出图比例 & 建议分辨率**：`1:1`（推荐 `2048×2048`）
- **切分对照（脚本自动切为 `256×256` 透明 PNG）**：

| 左 | 中 | 右 |
|---|---|---|
| `[1,1]` `coin_neon.png` (狂热霓虹) | `[1,2]` `coin_frost.png` (冰晶棱币) | `[1,3]` `coin_ghost.png` (幽灵穿影) |
| `[2,1]` `coin_jackpot7.png` (777轮盘币) | `[2,2]` `coin_blackhole.png` (黑洞奇点) | `[2,3]` `coin_giant.png` (黄金巨人) |
| `[3,1]` `coin_nuke.png` (核能烈焰) | `[3,2]` `coin_mini.png` (银分身) | `[3,3]` `coin_slag.png` (熔渣废币) |

#### 一键复制英文 Prompt（图集 2 · 进阶与衍生 9 币）
```text
Clean 3x3 grid sheet of 9 distinct game coin icons arranged neatly with generous empty space between every coin, NO grid lines, NO borders, NO dividers, isolated on a flat solid pure white #FFFFFF background (no ground shadow on white). Consistent 2.5D stylized neon arcade pop-art style, top-down slightly angled glossy coin tokens with chunky beveled metallic rims, 45-degree specular shine, bold dark ink outlines #090B16, zero unreadable text, zero watermark:
Row 1 Left: ultra-bright neon hot-pink disc coin #FF44DC with electric cyan outer rim and glowing five-point party star emblem;
Row 1 Center: icy translucent cyan sapphire coin #76EEFF featuring a geometric six-point snowflake crystal inside frosted glass;
Row 1 Right: semi-translucent ethereal ice-lavender ghost coin #AED2FF with a cute mischievous glowing spectral flame emblem;
Row 2 Left: gilded Vegas jackpot casino coin #FFD72E with neon pink-red marquee rim and glowing ornate golden 7 motif in center;
Row 2 Center: cosmic singularity obsidian black-hole void core coin surrounded by swirling neon violet-magenta accretion vortex #9C56FF;
Row 2 Right: massive extra-thick royal gold medallion coin #FFB224 with a bold golden king crown relief and double chamfered rim;
Row 3 Left: fiery molten magma nuke coin #FF4C2A encased in dark titanium ring with glowing radioactive flame trefoil emblem;
Row 3 Center: sleek polished chrome-silver mini coin #CADCF2 with a simple raised silver dot center and icy specular sheen;
Row 3 Right: rough volcanic dark iron slag coin #6A5E5C oozing bright glowing molten orange magma cracks across its scarred face.
```

#### 一键复制中文 Prompt（图集 2 · 国内生图工具直出）
```text
严格 3x3 规整九宫格排列的 9 枚独立游戏代币图标素材表，间距宽敞无任何网格框与黑线，纯白无杂质背景 #FFFFFF（无投影），无水印零杂字。统一 2.5D 霓虹街机潮酷波普风，微俯视斜角厚金属倒角币，45度高光与深蓝黑外描边 #090B16：
第一行左：荧光粉紫狂热霓虹硬币，带电青外圈与中央五角狂欢星徽记；
第一行中：冰蓝晶莹蓝宝石冰晶币，中央嵌几何六角冰晶雪花；
第一行右：幽蓝淡紫半透明幻影幽灵币，中央微光俏皮灵能小火苗；
第二行左：传奇黄金 777 轮盘币，红粉霓虹跑马灯圈与中心金色幸运数字 7；
第二行中：漆黑黑洞奇点核心币，四周环绕霓虹紫粉吸积盘漩涡；
第二行右：特大号双层切边皇家黄金巨人重币，正面厚实皇冠浮雕；
第三行左：黑钛外环裹烈焰红核的核能烈焰硬币，中央发光辐射火焰纹；
第三行中：轻巧高反光镀铬纯银迷你小币，正面简约银圆点突起；
第三行右：粗糙暗铁火山熔渣废币，布满炽热发光橙红岩浆裂纹。
```

---

### 2.3 图集 3：金库币 + 6 种进化传说币 + 2 件终极遗物 -> 保存为 `devtools/raw_sheets/sheet_03_coins_evo.png`

- **出图比例 & 建议分辨率**：`1:1`（推荐 `2048×2048`）
- **切分对照（前 7 枚切为 `256×256` 硬币，后 2 件切为 `192×192` 遗物，均透明底）**：

| 左 | 中 | 右 |
|---|---|---|
| `[1,1]` `coin_vault.png` (装甲金库币) | `[1,2]` `coin_midas.png` (点金圣王) | `[1,3]` `coin_thor.png` (雷神之锤) |
| `[2,1]` `coin_supernova.png` (超新星爆) | `[2,2]` `coin_hydra.png` (无限分身) | `[2,3]` `coin_singularity.png` (奇点涡轮) |
| `[3,1]` `coin_carnival.png` (狂欢大满贯) | `[3,2]` `relic_first_surge.png` (遗物·首冲引擎) | `[3,3]` `relic_prism.png` (遗物·霓虹棱镜) |

#### 一键复制英文 Prompt（图集 3 · 进化传说 7 币 + 2 终极遗物）
```text
Clean 3x3 grid sheet of 7 legendary arcade game coins (Rows 1-2 & Row 3 Left) plus 2 legendary cyber gadget icons (Row 3 Center & Right) with generous spacing, NO grid lines, NO borders, isolated on flat solid pure white #FFFFFF background (no shadow on white). Consistent 2.5D stylized neon arcade pop-art style, 45-degree glossy toy-like specular finish, bold dark ink outlines #090B16, zero text, zero watermark:
Row 1 Left: heavy armored golden cyber bank vault door coin #F0CE62 with electric cyan locking dial spokes and steel rim;
Row 1 Center: divine solar gold coin #FFE03E radiating halo glow with ornate royal sun-crown ruby core;
Row 1 Right: electrified storm coin #62E4FF with heavy gold rim framing a glowing cyber thunder warhammer crackling arcs;
Row 2 Left: cosmic starburst coin #FF5CAE with blinding white-gold fusion core radiating magenta and orange shockwaves;
Row 2 Center: bio-cyber emerald mint coin #52F8AE with interlocking three-way infinity spiral blades and glowing aqua crystal core;
Row 2 Right: deep cosmic ultraviolet turbine coin #964AFF with glowing cyan magnetic blades spinning around a dark void center;
Row 3 Left: ultimate prismatic rainbow-gold grand jackpot coin #FFCC40 with cyan-magenta aurora glaze and 8-point firework star;
Row 3 Center (gadget): glowing orange-cyan rocket turbocharger engine core brimming with stylized neon ignition flame bursts;
Row 3 Right (gadget): floating precision-cut holographic diamond crystal prism refracting beams of cyan, magenta and gold light.
```

#### 一键复制中文 Prompt（图集 3 · 国内生图工具直出）
```text
严格 3x3 规整九宫格排列，前 7 格为传说级街机硬币、右下最后 2 格为传说遗物装备图标，格子间隔宽松无框线、无分割线，纯白无杂质背景 #FFFFFF（无底影），零文字零水印。统一 2.5D 霓虹街机波普风格，45度亮泽高光与厚实深蓝黑外描边 #090B16：
第一行左：装甲黄金金库密码盘币，银铁加固边带荧光青锁盘辐条；
第一行中：点金圣王太阳金币，光芒光环配黄金红宝石王冠核；
第一行右：雷神之锤电光币，金银重装甲框内一把劈闪雷电的赛博战锤；
第二行左：超新星爆粉金恒星币，白金耀核向四周爆开品红橙色星环；
第二行中：无限分身翡翠晶核币，翠绿荧光三向无限循环螺旋刃；
第二行右：奇点涡轮紫电币，深黑虚空中心外旋一圈发光荧光青电磁扇叶；
第三行左：狂欢大满贯幻彩终极金币，金彩极光釉面与八芒庆典星徽；
第三行中（独立装备图标）：喷涌炽橙与电青尾焰的迷你火箭涡轮增压引擎核；
第三行右（独立装备图标）：悬浮半空的精切七彩全息钻石棱镜，折射青、品红、金色光束。
```

---

### 2.4 图集 4：9 件常规与经济遗物九宫格 -> 保存为 `devtools/raw_sheets/sheet_04_relics_a.png`

- **出图比例 & 建议分辨率**：`1:1`（推荐 `2048×2048`）
- **切分对照（脚本自动切为 `192×192` 透明 PNG，放入 `assets/image/relics/`）**：

| 左 | 中 | 右 |
|---|---|---|
| `[1,1]` `relic_rail_guard.png` (合金护栏) | `[1,2]` `relic_turbo_pusher.png` (涡轮活塞) | `[1,3]` `relic_golden_pegs.png` (黄金倍增钉) |
| `[2,1]` `relic_wide_gate.png` (宽口中奖门) | `[2,2]` `relic_metronome.png` (连击节拍器) | `[2,3]` `relic_medkit.png` (救急芯片) |
| `[3,1]` `relic_big_pouch.png` (大额币袋) | `[3,2]` `relic_bankbook.png` (复利金库) | `[3,3]` `relic_crit_seal.png` (暴击印章) |

#### 一键复制英文 Prompt（图集 4 · 遗物 A 组 9 件）
```text
Clean 3x3 grid sheet of 9 distinct stylized 2.5D cyber-arcade game gadget/relic icons neatly spaced apart, NO grid lines, NO borders, isolated on flat solid pure white #FFFFFF background (no shadow on white). Consistent 2.5D neon arcade pop-art toy-like glossy finish, 45-degree top-down lighting with subtle neon rim glint, bold dark ink outlines #090B16, zero text, zero watermark:
Row 1 Left: glowing neon cyan metallic arcade bumper shield rail #38E0FF with gold corner bolts;
Row 1 Center: chrome hydraulic piston spring coil glowing bright emerald-green kinetic aura #4AE88E;
Row 1 Right: trio of shiny golden pachinko bumper pins #FFD240 radiating bright cyan starlight sparks;
Row 2 Left: miniature glowing neon cyan #38E0FF and hot-magenta #FF48B2 arcade prize archway gate beaming gold light;
Row 2 Center: futuristic cyber metronome with bright glowing electric cyan lightning tempo needle #38E0FF;
Row 2 Right: cute rounded crimson neon cybernetic heart microchip #FF5260 with gold pins and crisp white cross emblem;
Row 3 Left: chunky deep-indigo leather arcade coin pouch tied with gold trim overflowing with shiny gold coins;
Row 3 Center: ornate compact golden cyber piggy-bank vault box #FFD240 locked with a glowing cyan combination dial;
Row 3 Right: fiery crimson-gold wax and metal stamp seal #FF5260 shaped like an explosive starburst with gold handle.
```

#### 一键复制中文 Prompt（图集 4 · 国内生图工具直出）
```text
严格 3x3 规整九宫格排列的 9 件游戏遗物/改装件独立图标，间距充足无格线无边框，纯白背景 #FFFFFF（无底影），无文字零水印。统一 2.5D 霓虹街机潮酷波普玩具质感，45度高光与清晰深蓝黑描边 #090B16：
第一行左：荧光青金属街机挡板护栏，四角带金螺栓；
第一行中：镀铬液压弹簧活塞推进器，泛翡翠绿动能光；
第一行右：三颗并排的亮黄金弹珠台倍增撞钉，带青金星火；
第二行左：袖珍青粉双色霓虹发光中奖门拱框；
第二行中：赛博未来风节拍器，中央一根发光荧光青闪电摆针；
第二行右：圆润火红色赛博机械爱心微芯片，金引脚配纯白十字标；
第三行左：鼓囊囊深靛蓝皮革街机金币束口袋，袋口溢出金币；
第三行中：袖珍精雕黄金赛博小金库扑满盒，带荧光青密码拨盘；
第三行右：金柄红宝石星爆火漆印章图标。
```

---

### 2.5 图集 5：9 件进攻与构筑遗物九宫格 -> 保存为 `devtools/raw_sheets/sheet_05_relics_b.png`

- **出图比例 & 建议分辨率**：`1:1`（推荐 `2048×2048`）
- **切分对照（脚本自动切为 `192×192` 透明 PNG，放入 `assets/image/relics/`）**：

| 左 | 中 | 右 |
|---|---|---|
| `[1,1]` `relic_fever_amp.png` (狂欢扩音器) | `[1,2]` `relic_double_barrel.png` (双发枪管) | `[1,3]` `relic_mag_lip.png` (磁力前沿) |
| `[2,1]` `relic_powder_keg.png` (超级火药) | `[2,2]` `relic_tesla_coil.png` (高压线圈) | `[2,3]` `relic_clover.png` (幸运四叶草) |
| `[3,1]` `relic_recycler.png` (回收磁爪) | `[3,2]` `relic_vip_card.png` (黄金会员卡) | `[3,3]` `relic_overclock.png` (超频散热) |

#### 一键复制英文 Prompt（图集 5 · 遗物 B 组 9 件）
```text
Clean 3x3 grid sheet of 9 distinct stylized 2.5D cyber-arcade game gadget/relic icons neatly spaced apart, NO grid lines, NO borders, isolated on flat solid pure white #FFFFFF background (no shadow on white). Consistent 2.5D neon arcade pop-art toy-like glossy finish, 45-degree top-down lighting with subtle neon rim glint, bold dark ink outlines #090B16, zero text, zero watermark:
Row 1 Left: retro-futuristic neon hot-magenta #FF48B2 and gold arcade megaphone speaker blasting glowing neon sound rings;
Row 1 Center: twin-bore gleaming chrome and neon cyan cybernetic coin launcher barrel nozzle #38E0FF;
Row 1 Right: glowing cyber violet #A672FF industrial electromagnet bar attracting tiny sparkling gold and cyan flecks;
Row 2 Left: chunky crimson-red and molten-gold hazard dynamite keg #FF5260 with neon warning stripes and lit fuse spark;
Row 2 Center: copper and electric-blue Tesla coil tower #38E0FF crackling bright cyan arcs around top chrome sphere;
Row 2 Right: radiant translucent emerald-crystal four-leaf clover brooch #4AE88E framed in gleaming golden wire;
Row 3 Left: cute cybernetic arcade claw-machine chrome pincer with cyan trim #38E0FF grabbing a shiny gold coin;
Row 3 Center: tilted luxury black-and-gold cyber VIP keycard #FFD240 embossed with a glowing royal crown symbol (no letters);
Row 3 Right: dual-fan neon gold #FFD240 and crimson #FF5260 cyber GPU cooling heatsink unit with glowing cyan fan blades.
```

#### 一键复制中文 Prompt（图集 5 · 国内生图工具直出）
```text
严格 3x3 规整九宫格排列的 9 件游戏遗物/改装件独立图标，间距充足无格线无边框，纯白背景 #FFFFFF（无底影），无文字零字母零水印。统一 2.5D 霓虹街机潮酷波普玩具质感，45度高光与清晰深蓝黑描边 #090B16：
第一行左：复古未来风粉金大声公扩音喇叭，喷出霓虹声波圈；
第一行中：镀铬双联荧光青赛博投币发射双枪管炮口；
第一行右：发光紫罗兰工业强力电磁铁条，吸附着细碎金色亮屑；
第二行左：红金配色警示条纹卡通火药炸药桶，顶端引线火花；
第二行中：铜线圈电光蓝特斯拉高压电塔，顶部金属球劈出蓝色电弧；
第二行右：金边镶嵌透明翡翠水晶四叶草幸运胸针；
第三行左：蓝金霓虹街机娃娃机机械抓爪，正抓起一枚金币；
第三行中：斜放的黑金奢华 VIP 皇冠徽记金卡（不要字母）；
第三行右：金红配色双风扇赛博超频散热器，扇叶泛荧光青光。
```

---

### 2.6 图集 6：7 件 UI 九宫格控件底图 + 2 件机台活动组件 -> 保存为 `devtools/raw_sheets/sheet_06_ui_machine.png`

- **出图比例 & 建议分辨率**：`1:1`（推荐 `2048×2048`）
- **切分对照（脚本按每格精确输出透明 PNG 到 `assets/image/ui/` 与 `assets/image/machine/`）**：

| 左 | 中 | 右 |
|---|---|---|
| `[1,1]` `ui/panel.png` (弹窗大框 `256×256`) | `[1,2]` `ui/card.png` (商店/奖励卡 `192×192`) | `[1,3]` `ui/slot.png` (小槽位 `128×128`) |
| `[2,1]` `ui/button.png` (金橙立体主按钮 `256×96`) | `[2,2]` `ui/plate.png` (顶栏底条 `256×96`) | `[2,3]` `ui/cloth.png` (底栏底板 `256×96`) |
| `[3,1]` `ui/banner.png` (标题飘带 `256×80`) | `[3,2]` `machine/pusher_bar.png` (往复推台 `512×128`) | `[3,3]` `machine/gate_badge.png` (中奖门 `160×64`) |

#### 一键复制英文 Prompt（图集 6 · UI 九宫格件 + 机台组件）
```text
Clean 3x3 grid sheet of 7 clean UI container frames (no text inside frames) plus 2 neon arcade pusher machine parts, wide clean spacing, NO grid lines, isolated on flat solid pure white #FFFFFF background. 2.5D stylized neon arcade pop-art game UI asset sheet, crisp dark outlines #090B16, no text, no watermark:
Row 1 Left: deep navy rounded rectangular UI panel frame #141830 with thick glowing cyan bevel border #38E0FF and corner rivets, clean empty middle for nine-slice;
Row 1 Center: dark indigo rounded UI card container #1C2242 with subtle purple-cyan gradient bevel rim and bottom drop lip, clean empty middle;
Row 1 Right: small square recessed dark navy UI slot socket #0E1022 with bright cyan-silver inner bevel rim, clean empty center;
Row 2 Left: glossy 3D chunky golden-amber pill button #FFD240 to #E88E18 with thick darker bottom bevel lip and bright top shine, clean empty center;
Row 2 Center: sleek horizontal dark slate metallic header bar plate #181E3C with glowing cyan bottom neon stripe #38E0FF, clean center;
Row 2 Right: horizontal brushed deep-navy bottom control bar plate #121834 with glowing hot-magenta top neon stripe #FF48B2, clean center;
Row 3 Left: bold bright electric cyan ribbon banner plate #38E0FF with white inner trim and chunky 3D bottom lip, clean empty center;
Row 3 Center: top-down 2.5D isometric arcade coin-pusher sliding shelf bar, purple-slate platform with glowing magenta front lip #FF48B2 and steel edge stripes;
Row 3 Right: futuristic neon jackpot gate arch bracket with twin glowing magenta bumpers framing a bright gold light beam chute.
```

#### 一键复制中文 Prompt（图集 6 · 国内生图工具直出）
```text
严格 3x3 规整九宫格排列的游戏 UI 边框套件与 2 个推币机台部件，纯白背景 #FFFFFF（无投影），格子间距宽松不画任何格线或黑框，全部中间留干净以便做九宫格拉伸，画面严禁任何文字字母，2.5D 霓虹街机波普风格与深蓝黑描边 #090B16：
第一行左：深海军蓝圆角大弹窗底框，外圈荧光青立体边框配四角金属铆钉；
第一行中：深靛蓝微凸商品/奖励卡片底框，紫青渐变倒角边框带底边立体厚度；
第一行右：内凹暗夜蓝正方形格位小槽，带银青色内框高光；
第二行左：饱满亮金橙色 3D 立体胶囊主按钮，厚实深琥珀底边与顶部高光反光条；
第二行中：横向深铁灰金属顶栏长条板，底边一条荧光青霓虹灯带；
第二行右：横向拉丝深蓝底栏金属底座条，顶边一条霓虹粉品红灯带；
第三行左：电光青立体飘带标题横幅底图，内圈白线点缀；
第三行中：2.5D 微俯视推币机推板台，紫灰金属平台加超亮荧光品红推进前唇；
第三行右：左右双品红撞柱加中间金色光柱的街机中奖门机关组件。
```

> 放好以上 7 张 UI PNG 后，在 [`scripts/game/Skin.lua`](../scripts/game/Skin.lua#L17) 填入：
> ```lua
> Skin.TEXTURES.panel  = { image = "image/ui/panel.png",  slice = { 24, 24, 24, 24 } }
> Skin.TEXTURES.card   = { image = "image/ui/card.png",   slice = { 18, 18, 18, 18 } }
> Skin.TEXTURES.slot   = { image = "image/ui/slot.png",   slice = { 14, 14, 14, 14 } }
> Skin.TEXTURES.button = { image = "image/ui/button.png", slice = { 14, 18, 20, 18 } }
> Skin.TEXTURES.plate  = { image = "image/ui/plate.png",  slice = { 10, 12, 14, 12 } }
> Skin.TEXTURES.cloth  = { image = "image/ui/cloth.png",  slice = { 14, 12, 10, 12 } }
> Skin.TEXTURES.banner = { image = "image/ui/banner.png", slice = { 12, 24, 14, 24 } }
> ```

---

### 2.7 图集 7：3 幕机台背板 + 6 幅奇遇事件插画九宫格 -> 保存为 `devtools/raw_sheets/sheet_07_scenes_events.png`

- **出图比例 & 建议分辨率**：`1:1`（推荐 `2048×2048`，每一格均为**不透明暗夜赛博场景图**，脚本会自动裁剪白边与分界并适配到 `512×480` 与 `512×240`）
- **切分对照**：

| 左 | 中 | 右 |
|---|---|---|
| `[1,1]` `machine/backdrop_act1.png` (1幕·霓虹游艺厅) | `[1,2]` `machine/backdrop_act2.png` (2幕·黄金熔炉) | `[1,3]` `machine/backdrop_act3.png` (3幕·赛博金库) |
| `[2,1]` `events/event_gold_altar.png` (黄金祭坛) | `[2,2]` `events/event_scrap_smith.png` (机台改造匠) | `[2,3]` `events/event_lucky_wheel.png` (午夜赌局) |
| `[3,1]` `events/event_neon_spring.png` (狂欢充能站) | `[3,2]` `events/event_magnet_trap.png` (废料清道夫) | `[3,3]` `events/event_vault_crack.png` (加密金库门) |

#### 一键复制英文 Prompt（图集 7 · 3 幕背板 + 6 大奇遇场景插画）
```text
Tight 3x3 collage grid of 9 dark neon cyber-arcade scene panels with crisp clean framing and zero UI overlays (no text, no letters, no watermark). Consistent 2.5D stylized neon arcade pop-art illustration style, rich dark navy shadows #0A0C1A, bold dark ink outlines #090B16:
Row 1 Left: Act 1 Neon Arcade Hall coin-pusher backboard texture, deep purple-navy cyber grid with glowing cyan #38E0FF and magenta #FF48B2 side neon rails and dark uncluttered center;
Row 1 Center: Act 2 Molten Gold Furnace machine backboard texture, bronze-obsidian industrial foundry wall with glowing orange magma pipes on edges and dark center;
Row 1 Right: Act 3 Cyber Vault machine backboard texture, obsidian armored vault steel wall with violet #A672FF and radiant gold laser lock lines on sides and clean dark center;
Row 2 Left: ancient glowing golden slot-machine altar #FFD240 in a purple temple with twin cyan and crimson coin light beams;
Row 2 Center: cozy workshop where a friendly goblin-robot mechanic with glowing cyan goggles #38E0FF forges glowing golden coins on an anvil;
Row 2 Right: extravagant neon hot-magenta #FF48B2 and gold roulette fortune wheel spinning in midnight velvet spotlight with floating casino chips;
Row 3 Left: vertical glowing magenta #FF48B2 and violet #A672FF plasma battery energy fountain bubbling with golden sparks inside an arcade bay;
Row 3 Center: giant violet electromagnetic crane lifting dull dark iron coins into a glowing cyan #38E0FF vortex over gleaming gold coins;
Row 3 Right: massive armored gold cyber bank vault door slightly cracked open with crisscrossing cyan lasers and golden treasure light pouring out.
```

#### 一键复制中文 Prompt（图集 7 · 国内生图工具直出）
```text
规整 3x3 九宫格的 9 幅暗夜赛博街机风场景插画图集，每格填满深色调场景画幅（无白边、严禁任何文字与UI按钮），统一 2.5D 霓虹街机潮酷波普手绘描边风格 #090B16，深蓝夜色主调：
第一行左：第1幕「霓虹游艺厅」机台背板——深紫几何网格，两侧荧光青粉灯带，正中干净微暗衬托落币；
第一行中：第2幕「黄金熔炉」机台背板——黑铜工业熔炉板，两侧橘金熔岩管道，正中暗调留空；
第一行右：第3幕「赛博金库」机台背板——黑曜石装甲金库门板，两侧紫金激光防线，正中暗调留空；
第二行左：「黄金祭坛」奇遇——幽紫神殿里发出金青粉光束的双投币孔古老黄金祭坛；
第二行中：「机台改造匠」奇遇——戴荧光青护目镜的友善机械哥布林铁匠在霓虹铁砧前锻造金币；
第二行右：「午夜赌局」奇遇——暗夜聚光灯下旋转的粉金奢华幸运转盘与飞舞筹码；
第三行左：「狂欢充能站」奇遇——紫粉发光等离子能量柱喷泉，冒泡飞出金星火花；
第三行中：「废料清道夫」奇遇——巨型紫色工业电磁铁吊爪抓走废铁渣币、留下闪亮金币；
第三行右：「加密金库门」奇遇——厚重黄金装甲金库大门微开一道缝，射出青色激光与耀眼金光。
```

---

### 2.8 图集 8：三大守关 Boss 横版三连拼图 -> 保存为 `devtools/raw_sheets/sheet_08_bosses.png`

- **出图比例 & 建议分辨率**：`16:9` 或 `3:1` 宽屏横排（推荐 `2048×1152` 或 `2400×800`，从左到右等距横排 3 位 Boss，脚本自动抠白底输出 `256×256` 透明 PNG）
- **切分对照**：
  - 左 1/3 -> `assets/image/boss/boss_gatekeeper.png`（第 1 幕 · 铁闸庄家）
  - 中 1/3 -> `assets/image/boss/boss_furnace.png`（第 2 幕 · 熔金巨轮）
  - 右 1/3 -> `assets/image/boss/boss_vaultbeast.png`（第 3 幕 · 终极吞金兽）

#### 一键复制英文 Prompt（图集 8 · 3 大 Boss 三连图）
```text
Clean 3-column horizontal lineup sheet of 3 distinct arcade boss character portraits arranged side by side from left to right with wide empty spacing between each character, NO divider lines, NO borders, isolated on a flat solid pure white #FFFFFF background (no shadow cast on white). Consistent 2.5D stylized neon arcade pop-art style, 45-degree glossy toy-metallic shading, bold dark ink outlines #090B16, zero text, zero watermark:
Left portrait: The Iron Gatekeeper, imposing armored cyber-casino robot torso wearing a neon gold crown #FFD240, glowing electric cyan visor eyes #38E0FF, and heavy laser-barrier gauntlets;
Center portrait: Molten Furnace Wheel, giant heavy cyber-foundry rotary core machine bursting with glowing orange-gold magma gears #FFD240, molten slag vents, and fiery red core #FF5260;
Right portrait: Cyber Vault Leviathan, menacing armored purple-and-gold mechanical dragon-mimic chest beast #A672FF with glowing vault combination dial jaw, sharp golden teeth, and neon cyan energy veins.
```

#### 一键复制中文 Prompt（图集 8 · 国内生图工具直出）
```text
横向一字等距排开的 3 位守关 Boss 立绘三连拼图（左中右三等分，彼此留宽白间距，不画分割线不画框），纯白无杂质背景 #FFFFFF（无底影），无任何文字字母。统一 2.5D 霓虹街机潮酷波普风格，亮泽厚涂金属反光与粗黑深蓝描边 #090B16：
左侧：第1幕Boss「铁闸庄家」——威严的重装甲赛博游艺机甲半身像，头戴霓虹金冠，发光电青目镜，双手戴激光护闸拳套；
中间：第2幕Boss「熔金巨轮」——巨大厚重的蒸汽赛博熔炉巨轮核心，燃烧着橘红岩浆齿轮与喷吐熔金渣的排气口；
右侧：第3幕终极Boss「终极吞金兽」——凶悍的紫金机械巨龙金库宝箱怪，下颌是发光金库密码转盘与闪亮金牙，周身游走荧光青能量脉络。
```

---

## 三、宣发素材三件套（均已独立完整，可直接复制生成）

### 3.1 `1:1` 游戏头像 / 主图标（3×3 九宫格动感展示矩阵，推荐出图 `1024×1024` / `2048×2048`）

#### 一键复制英文 Prompt（1:1 头像九宫格）
```text
A tight 3x3 square grid collage divided cleanly by thin dark border lines into 9 equal panels, showcasing 9 dynamic close-up icons and highlight moments of a stylized 2.5D Neon Arcade Coin-Pusher roguelike game, glossy toy-like 45-degree top-down rendering, bold dark outlines #090B16, deep midnight navy backdrops (#0A0C1A), NO text, NO letters, NO UI frames:
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

#### 一键复制中文 Prompt（1:1 头像九宫格 · 国内直出）
```text
严格均分 3x3 九宫格拼图展示，细暗线清晰隔开 9 个等大正方形画面，呈现 2.5D 霓虹街机风肉鸽推币游戏的 9 个核心代币与高光瞬间，潮酷厚涂硬边深色描边，45度高光琉璃玩具质感，深海午夜暗蓝底色，画面中严禁出现任何文字、数字、按钮或UI框：
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

### 3.2 `16:9` 横版主视觉宣传图（Key Art · 已强约束左上 35% 标题安全区，推荐 `1920×1080`）

#### 一键复制英文 Prompt（16:9 横版宣传图）
```text
16:9 horizontal widescreen key art illustration for a 2.5D stylized Neon Arcade Roguelike Coin-Pusher game, ultra-vibrant cyber pop-art 45-degree glossy lighting, bold crisp dark ink outlines #090B16.
Composition weighted heavily to the right and bottom-right: an angled heroic view of a towering futuristic cyber-arcade coin-pusher machine glowing with electric cyan #38E0FF and hot magenta #FF48B2 neon rails. Hundreds of glossy gold coins, emerald clover tokens, crackling blue lightning coins, fiery bomb coins, and a gleaming rainbow 777 jackpot centerpiece burst forward off the sliding neon pusher shelf like an unstoppable golden waterfall cascade, sending luminous sparkles and energy arcs spraying toward the camera.
Top-left corner composition rule: keep the upper-left 35% of the frame clean, spacious, deep dark midnight-blue cyber twilight sky (#0A0C1A) with only soft out-of-focus bokeh neon lights as a dedicated empty negative-space title safe zone.
Zero text, zero letters, zero logos, zero UI HUD elements anywhere in the artwork.
```

#### 一键复制中文 Prompt（16:9 横版宣传图 · 国内直出）
```text
16:9 横版高清游戏主视觉宣传插画，2.5D 霓虹街机潮酷波普风格，厚涂硬边深色描边与晶莹糖果高光质感。
构图重心置于画面右侧与右下方：大透视角度展示一座闪耀着荧光青与霓虹品红灯管的未来赛博推币机台，发光推板猛烈推出层层叠叠的金色硬币海啸，夹杂着闪电蓝币的跳跃电弧、爆炸火红币的冲击火花、翡翠幸运币以及悬浮在潮头最亮眼的幻彩777大满贯币，成百上千枚硬币正如黄金瀑布般向镜头前方倾泻爆发！
关键安全区约束：画面左上角 35% 区域必须保持干净深邃的暗夜藏青虚化霓虹散景留白，留作后期排版游戏主标题的安全空区，不要画满复杂前景物。
画面中绝对不要生成任何文字、字母、水印或游戏UI边框。
```

---

### 3.3 `16:9` 15 秒宣传片视频脚本与整段直出提示词（Sora2 / Veo / Kling 通用）

#### 一键复制完整连续英文视频 Prompt（16:9 · 15 秒）
```text
15-second continuous high-energy 16:9 stylized 2.5D neon arcade game showcase trailer, ultra-smooth 60fps camera work, glossy cyber-pop art style with deep midnight navy backdrop (#0A0C1A), electric cyan (#38E0FF), hot magenta (#FF48B2), and glowing gold (#FFD240) VFX, zero UI text overlays:
[0s-3s Opening Aim & Pin Drop] Dynamic vertical tilt down a sleek cyber coin-pusher arcade cabinet: a gleaming gold coin drops from the top chute, zigzags cleanly down glowing cyan and amber pachinko pegs emitting bright sparks, and threads dead-center through a sliding neon magenta jackpot gate archway.
[3s-7s Escalation & Elemental Chain Reaction] The camera glides lower toward the metallic pusher shelf packed wall-to-wall with shimmering coins; an electric blue thunder coin lands and arcs jagged cyan lightning chains across 6 neighboring coins while an orange bomb coin detonates a punchy warm shockwave pushing the front row to the brink.
[7s-12s Fever Climax Waterfall] The entire arcade cabinet borders flash brilliant gold-pink Fever mode; the glowing magenta pusher bar surges rapidly forward as a dazzling torrent of fifty golden and emerald coins pours from above like a waterfall, unleashing a colossal avalanche of glittering coins spilling nonstop off the front ledge in slow-motion bursts of golden light rays.
[12s-15s Hero Finale Freeze] The camera pulls back slightly with triumphant confetti sparks and rainbow aurora glow radiating around a gleaming central 777 mega-coin emerging over the overflowing vault tray, landing in a clean dramatic final hero hold with open dark bokeh room on the upper side for end-slate logo placement.
```

#### 分段精调备查（四幕时间戳对照）
| 时间轴 | 阶段名 | 镜头与主体动作 | 配合音频/后期花字建议 |
|---|---|---|---|
| `0s – 3s` | **摆动狙门开局** | 镜头随顶槽金币坠落，连撞霓虹钉迸火星后直穿滑动品红中奖门 | `peg1` → `peg_mult` → `gate_win` |
| `3s – 7s` | **连锁元素引爆** | 镜头下压对准推台：霹雳币劈 5 段闪电、炸弹币震荡掀推整排前币 | `zap` + `explode` + 鼓点切入 |
| `7s – 12s` | **Fever 狂欢瀑布** | 全机台暴闪金粉边框，推板超频急进 + 五十枚金币雨瀑布式倾泻 | `fever` + `crit` + `drop` 连响 |
| `12s – 15s` | **777 大满贯定格** | 拉远定格幻彩 777 巨币海啸，上方留出暗青虚化空区贴 Logo | `jackpot` + `win` + 片尾标题 |

---

## 四、已合入成品验收后的返工整合图（仅 1 张 `2×1` 横拼 -> `devtools/raw_sheets/sheet_09_rework.png`）

经 `UrhoXRuntime` 8 屏实机截图与全表检视，其余 70 张贴图均已清晰生效，仅下列 **2 个格位**建议合并为一整张 `2×1`（`16:9` 或 `2:1`，推荐 `2048×1024`）返工生成，保存为 `devtools/raw_sheets/sheet_09_rework.png` 后再次运行 `devtools\slice_sheets.py` 即可自动覆盖对应遗物、主按钮及全部 6 色衍生按钮：

| 左 `[1,1]` | 右 `[1,2]` |
|---|---|
| `relics/relic_golden_pegs.png`（黄金钉阵：`sheet_04` 原图错画成了保龄球瓶，需重绘为霓虹街机发光黄金弹珠撞针柱群） | `ui/button.png`（九宫格通用主按钮：`sheet_06` 原图左上角存在刺眼白色光斑与过度椭圆端头，需重绘为高光均匀、中间 60% 平滑的圆角金橙立体按钮条） |

#### 一键复制英文 Prompt（返工整合图 · 2 项合 1）
```text
Clean 2x1 horizontal side-by-side game UI & icon sprite sheet with generous empty margin between the two items, NO grid lines, NO borders, NO dividers, isolated on a flat solid pure white #FFFFFF background (no shadow cast on white). Consistent 2.5D stylized neon arcade pop-art game art style, bold dark ink outlines #090B16, zero text, zero watermark:
Left item [1,1]: cluster of three chunky glowing golden metallic pinball/pachinko bumper pegs mounted upright on a small sleek dark cyber base plate, radiant amber-gold #FFD240 dome caps with glowing neon cyan #38E0FF energy rings pulsing around each peg collar, clearly a coin-pusher pegboard bumper set (NOT bowling pins);
Right item [1,2]: clean horizontal glossy rounded-rectangle arcade UI button bar #FFD240 to #E88E18 (moderate corner radius, NOT extreme capsule ends) with even soft horizontal top rim shine (NO off-center spotlight glare blob), crisp chunky darker amber bottom 3D bevel lip, completely uniform smooth flat golden middle area designed for clean UI 9-slice stretching, empty inside with zero text.
```

#### 一键复制中文 Prompt（返工整合图 · 国内直出）
```text
严格左右 2x1 横排的 2 个游戏素材整合图，两件素材之间保留充足纯白留白，严禁画任何分割线或边框，纯白无杂质背景 #FFFFFF（无底影），无任何文字、字母或水印。统一 2.5D 霓虹街机潮酷波普风，清晰深蓝黑描边 #090B16：
左边第 1 格 [1,1]：一组三个立在深色迷你科技底座上的发光黄金街机弹珠撞针柱（推币机/弹珠台金属撞钉，圆顶蘑菇钉帽配底座荧光青环形灯圈，明确不是保龄球瓶），45度斜顶琉璃光泽；
右边第 2 格 [1,2]：水平居中横放的圆角矩形金橙立体游戏 UI 主按钮条，适度圆角（不要过度窄椭圆胶囊），顶部仅有一条均匀柔和的细高光边（严禁左上角大块白色反光刺眼圆斑），底部带厚实深橙 3D 立体底边，按钮中间 60% 区域完全平整光滑无花纹以便做九宫格无缝拉伸，内部空白无文字。
```

#### 返工完成后一键覆盖命令
```powershell
"C:\Users\Administrator\.taptap-maker\python\uv\cpython-3.12-windows-x86_64-none\python.exe" "devtools\slice_sheets.py"
```
