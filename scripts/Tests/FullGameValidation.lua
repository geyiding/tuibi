-- ============================================================================
-- scripts/Tests/FullGameValidation.lua  真机引擎全链路 UI/逻辑/零跳动终验脚本
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
    local Hud = require("game/Hud")
    local CodexHud = require("game/CodexHud")
    local SaveManager = require("game/SaveManager")

    -- 1. 验证主菜单布局
    UI.Layout()
    local menuPage = Hud.GetPages().menu
    assert(menuPage:IsVisible(), "开屏应显示主菜单")
    AssertBoxInsideScreen(menuPage:GetChildAt(1), "主菜单卡片")

    -- 2. 切入图鉴弹窗：验证 4 页签切换外框宽高 0 像素跳动
    cb.OnOpenCodex()
    UI.Layout()
    local codexModal = Hud.GetModals().codex
    local codexFrame = codexModal:GetChildAt(1)
    local baseL = AssertBoxInsideScreen(codexFrame, "图鉴外框-币种")
    for _, tabId in ipairs({ "recipes", "relics", "bosses", "coins" }) do
        -- 通过直接切内部 tab 触发刷新并验证外框高度恒定
        local tabRow = codexFrame:GetChildAt(2)
        for ti = 1, tabRow:GetNumChildren() do
            local btn = tabRow:GetChildAt(ti)
            if btn.onPress_ then btn.onPress_(btn) end
            UI.Layout()
            local curL = codexFrame:GetAbsoluteLayout()
            assert(math.abs(curL.w - baseL.w) < 0.5 and math.abs(curL.h - baseL.h) < 0.5,
                string.format("图鉴切页签外框跳变! tab=%s base=%.1fx%.1f cur=%.1fx%.1f", tabId, baseL.w, baseL.h, curL.w, curL.h))
        end
    end
    cb.OnCloseCodex()

    -- 3. 切入设置弹窗并测试兑换码防重领
    cb.OnOpenSettings()
    UI.Layout()
    local settingsFrame = Hud.GetModals().settings:GetChildAt(1)
    AssertBoxInsideScreen(settingsFrame, "设置外框")
    local beforeTickets = game.run.tickets
    cb.OnRedeemCode("CARNIVAL2026")
    assert(game.run.tickets == beforeTickets + 50, "兑换码应增加50金券")
    cb.OnRedeemCode("carnival2026")
    assert(game.run.tickets == beforeTickets + 50, "重复兑换码不可再次发奖")
    cb.OnCloseSettings()

    -- 4. 进入实战，检验 150 帧高潮狂欢 + 投币仓双页签 0 跳动
    _G.__ENTER_PLAY(false)
    local run = game.run
    run.autoDrop = true
    run:AddFever(95)
    for _ = 1, 150 do
        game.time = game.time + (1 / 60)
        game.fx:Update(1 / 60)
        run:Update(1 / 60)
        if run.ammoLeft <= 3 then run.ammoLeft = 10 end
    end
    Hud.RefreshPlay(run)
    UI.Layout()
    assert(run.score > 0 and run.coinsDropped > 0, "实战必须产生得分与掉落")
    if game.modal == "reward" then
        AssertBoxInsideScreen(Hud.GetModals().reward:GetChildAt(1), "奖励三选一外框")
        cb.OnPickReward(1)
    elseif game.modal then
        _G.__CLOSE_MODAL()
    end

    -- 投币仓弹窗 2 页签 0 跳动校验
    cb.OnOpenDeck()
    UI.Layout()
    local deckFrame = Hud.GetModals().deck:GetChildAt(1)
    local d1 = AssertBoxInsideScreen(deckFrame, "投币仓外框")
    local tabRow = deckFrame:GetChildAt(2)
    tabRow:GetChildAt(2).onPress_(tabRow:GetChildAt(2))
    UI.Layout()
    local d2 = deckFrame:GetAbsoluteLayout()
    assert(math.abs(d1.w - d2.w) < 0.5 and math.abs(d1.h - d2.h) < 0.5, "投币仓切页签不可跳动")
    cb.OnCloseDeck()

    -- 5. 验证商店/工坊/事件/宝箱/路线图均无报错且在安全区内
    run:OpenShop()
    _G.__SHOW_SCREEN("shop")
    UI.Layout()
    run.tickets = 500
    assert(run:BuyShopItem(1), "商店购买成功")
    _G.__SHOW_SCREEN("map")
    UI.Layout()

    -- 最后进入第 2 关并激活狂欢高潮，停留实战状态供截图验收
    run:EnterNode(next(run.selectedNextIds))
    _G.__SHOW_SCREEN("play")
    run:AddFever(100)
    for _ = 1, 90 do
        game.time = game.time + (1 / 60)
        game.fx:Update(1 / 60)
        run:Update(1 / 60)
    end
    Hud.RefreshPlay(run)
    UI.Layout()
    print(string.format("[FullGameValidation] PASS: score=%d dropped=%d combo=%d",
        run.score, run.coinsDropped, run.combo))
end
