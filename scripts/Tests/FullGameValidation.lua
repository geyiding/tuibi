-- ============================================================================
-- scripts/Tests/FullGameValidation.lua  世界首富增量版全链路 UI/逻辑终验脚本
-- ============================================================================

require("main")
local origStart = Start
local UI = require("urhox-libs/UI")

local function AssertBoxInsideScreen(w, label)
    local l = w:GetAbsoluteLayout()
    local sw, sh = UI.GetWidth(), UI.GetHeight()
    assert(l.w > 0 and l.h > 0, label .. " 尺寸不可为0")
    assert(l.x >= -1 and l.y >= -1 and l.x + l.w <= sw + 1 and l.y + l.h <= sh + 1,
        string.format("%s 超出屏幕安全边界: (%.1f,%.1f %.1fx%.1f) vs %.1fx%.1f", label, l.x, l.y, l.w, l.h, sw, sh))
    return l
end

function Start()
    origStart()
    local game = _G.__GAME
    local cb = _G.__CALLBACKS
    local TycoonHud = require("game/TycoonHud")
    local ty = game.tycoon
    assert(ty ~= nil, "开屏必须立即就绪增量首富实例")

    -- 1. 注入启动资金 + 模拟 150 帧自动永动推币 + 狂欢反馈
    UI.Layout()
    local root = UI.GetRoot()
    assert(root ~= nil and root:GetNumChildren() >= 2, "根界面与弹窗层必须就绪")
    ty:TriggerFever(true)
    for _ = 1, 150 do
        game.time = game.time + (1 / 60)
        game.fx:Update(1 / 60)
        ty:Update(1 / 60)
    end
    TycoonHud.RefreshMain(ty)
    UI.Layout()
    assert(ty.cash > 0 and ty.lifetimeCash > 0, "150帧自动推币必须产出正向现金流")

    -- 2. 注入研发资金验证全养成弹窗边界与零报错刷新
    ty.cash = ty.cash + 500000
    ty.lifetimeCash = ty.lifetimeCash + 500000
    assert(ty:BuyMachineUpgrade("auto_rate", 1), "机台自动速率升级必须成功")
    assert(ty:BuyCoin("emerald"), "翡翠币解锁必须成功")
    assert(ty:BuyTech("rail_guard"), "护栏黑科技解锁必须成功")

    for _, modalName in ipairs({ "machine", "coins", "tech", "prestige", "welfare", "ranks", "formula" }) do
        TycoonHud.OpenModal(modalName)
        UI.Layout()
        for i = 2, root:GetNumChildren() do
            local layer = root:GetChildAt(i)
            if layer:IsVisible() and layer:GetNumChildren() >= 1 then
                AssertBoxInsideScreen(layer:GetChildAt(1), "弹窗-" .. modalName)
            end
        end
    end
    TycoonHud.CloseModal()

    -- 2.5 测试富豪超越即时漫画头像弹窗边界与正常收下
    local Config = require("game/Config")
    TycoonHud.ShowOvertake(Config.RANKS[100], { jumped = 1, bounty = Config.RANKS[100].bounty, wealthNow = Config.RANKS[100].target })
    UI.Layout()
    TycoonHud.DismissOvertake()

    -- 3. 模拟激励广告播放完成回调（绝不触发外部 SDK）
    cb.OnWatchAd("boost_3x")
    assert(TycoonHud.GetCurModal() == "mockAd", "点击激励广告必须打开模拟广告弹窗")
    UI.Layout()
    cb.OnMockAdFinish()
    assert(ty.adBoostLeft > 0, "模拟广告领奖必须激活 3 倍印钞")

    -- 4. 设置与兑换码防重领
    cb.OnOpenSettings()
    UI.Layout()
    local beforeCash = ty.cash
    cb.OnRedeemCode("CARNIVAL2026")
    assert(ty.cash > beforeCash, "兑换码 CARNIVAL2026 必须发奖")
    local afterFirst = ty.cash
    cb.OnRedeemCode("carnival2026")
    assert(ty.cash == afterFirst, "重复兑换码不可再次发奖")
    cb.OnCloseSettings()

    -- 5. 验证 IPO 转生与重置重推
    ty.runCash = 2500000
    local gained = ty:DoPrestige(false)
    assert(gained > 0 and ty.prestigeShares >= gained, "IPO 转生必须获得传奇股")
    for _ = 1, 60 do
        game.time = game.time + (1 / 60)
        game.fx:Update(1 / 60)
        ty:Update(1 / 60)
    end
    TycoonHud.RefreshMain(ty)
    UI.Layout()

    print(string.format("[FullGameValidation] PASS: cash=%.0f lifetime=%.0f shares=%d drops=%d",
        ty.cash, ty.lifetimeCash, ty.prestigeShares, ty.totalDrops))
end
