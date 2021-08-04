-- Todo
-- Player(De)BuffMissing, Friend(De)BuffMissing, Enemy(De)BuffMissing
-- Player(De)BuffAlert, Friend(De)BuffAlert, Enemy(De)BuffAlert
-- PlayerBuffAlert -> PlayerBuffAlert
-- Border Color

--/script local start, duration, enabled = GetSpellCooldown("신성화"); DEFAULT_CHAT_FRAME:AddMessage("Width: " .. start .. "/" .. duration .. "/" .. enabled);
--/script DEFAULT_CHAT_FRAME:AddMessage("Width: " .. UnitDebuff("target", 1));
--/script local name, rank, icon, count, school, duration, expiryTime = UnitDebuff("target", 1); DEFAULT_CHAT_FRAME:AddMessage("Width: " .. name .. "/" .. duration .. "/" .. expiryTime);

local debug = nil;

-- Slot Variables

local MAX_BUFF_SLOT = 6;
local BUFF_SLOT_SIZE = 50;
local ACTION_SLOT_SIZE = 40;
local NUM_ACTION_SLOT = 10;
local playerBuffSlots = {};
local playerDebuffSlots = {};
local targetBuffSlots = {};
local targetDebuffSlots = {};
local actionSlots = {};
local actionUpdateSlots = {};
local activatedSpells = {};

-- Helper

-- /script local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = UnitBuff("player", 4); DEFAULT_CHAT_FRAME:AddMessage(name..": "..spellId);

local spellIds = {};
spellIds["차크라: 평온"] = 81208;

local function GetSpellTextureEx(name)
    spellId = spellIds[name];
    if spellId ~= nil then
        return GetSpellTexture(spellId);
    end
    return GetSpellTexture(name);
end

-- Slot APIs

local function CreateSlot(size)
    local slot = CreateFrame("frame", nil, UIParent);
    slot:SetWidth(size);
    slot:SetHeight(size);
    slot:SetAlpha(0.5);
    slot:SetScale(1.54);
--    slot:SetScale(1 / UIParent:GetEffectiveScale());
--/script DEFAULT_CHAT_FRAME:AddMessage(1 / UIParent:GetEffectiveScale());
    slot.icon = slot:CreateTexture();
    slot.icon:SetPoint("CENTER");
    slot.icon:SetWidth(size);
    slot.icon:SetHeight(size);

    slot.text1 = slot:CreateFontString(nil, 0, "NumberFontNormalHuge"); slot.text1:SetPoint("TOPLEFT");
    slot.text2 = slot:CreateFontString(nil, 0, "NumberFontNormalHuge"); slot.text2:SetPoint("TOPRIGHT");
    slot.text3 = slot:CreateFontString(nil, 0, "NumberFontNormalHuge"); slot.text3:SetPoint("BOTTOMLEFT");
    slot.text4 = slot:CreateFontString(nil, 0, "NumberFontNormalHuge"); slot.text4:SetPoint("BOTTOMRIGHT");
    slot.text5 = slot:CreateFontString(nil, 0, "NumberFontNormalHuge"); slot.text5:SetPoint("CENTER");

    slot:Show();

    local function SetSlotText(fontstring, text)
        if (text ~= nil) then
            fontstring:SetText(text);
            fontstring:Show();
        else
            fontstring:Hide();
        end
    end

    function slot:SetSlot(icon, tl, tr, bl, br, center)
        if (icon ~= nil) then
            self.icon:SetTexture(icon);
            self.icon:Show();
        else
            self.icon:Hide();
        end

        SetSlotText(self.text1, tl);
        SetSlotText(self.text2, tr);
        SetSlotText(self.text3, bl);
        SetSlotText(self.text4, br);
        SetSlotText(self.text5, center);

        self:Show();
    end

    function slot:SetCooldown(icon, cooldown)
        if (icon ~= nil) then
            self.icon:SetTexture(icon);
            self.icon:Show();
        else
            self.icon:Hide();
        end

        SetSlotText(self.text5, cooldown);
	if (cooldown == nil) then
            slot:SetAlpha(0.8);
	else
            slot:SetAlpha(0.3);
	end

        self:Show();
    end

    return slot;
end

local function CreateSlots(slots, count, size, xoffset, yoffset, left)
    local myanchor = "LEFT";
    local targetanchor = "RIGHT";
    if (left) then
        myanchor = "RIGHT";
        targetanchor = "LEFT";
    end

    slots[1] = CreateSlot(size); slots[1]:SetPoint("CENTER", xoffset, yoffset);
    for i = 2, count do
        slots[i] = CreateSlot(size); slots[i]:SetPoint(myanchor, slots[i - 1], targetanchor);
    end

    slots.index = 1;

    function slots:AddSlotTex(icon, tl, tr, bl, br)
        if self.index <= MAX_BUFF_SLOT then
            self[self.index]:SetSlot(icon, tl, tr, bl, br);
            self.index = self.index + 1;
        end
    end

    function slots:AddSlotBuff(func, buff)
--        debug:SetText(buff);
        local icon, count, duration, timeLeft = func(buff);
        if (timeLeft ~= nil) then
            timeLeft = math.ceil(timeLeft);
        end
        if (count == 0) then
            count = nil;
        end
        if (icon == nil) then
            icon = GetSpellTextureEx(buff);
            if (icon == nil) then
                icon = GetSpellTextureEx(v .. "()");
            end
        end
        self:AddSlotTex(icon, nil, timeLeft, nil, count);
    end
end


local function CreateAllSlots()
    CreateSlots(playerBuffSlots,   MAX_BUFF_SLOT, BUFF_SLOT_SIZE, -200,  40, true);
    CreateSlots(playerDebuffSlots, MAX_BUFF_SLOT, BUFF_SLOT_SIZE, -200, -40, true);
    CreateSlots(targetBuffSlots,   MAX_BUFF_SLOT, BUFF_SLOT_SIZE,  200,  40, false);
    CreateSlots(targetDebuffSlots, MAX_BUFF_SLOT, BUFF_SLOT_SIZE,  200, -40, false);

    local xoffset = -(ACTION_SLOT_SIZE * (NUM_ACTION_SLOT - 1) / 2);
    CreateSlots(actionSlots, NUM_ACTION_SLOT, ACTION_SLOT_SIZE, xoffset, -130, false);
    for i = 1, NUM_ACTION_SLOT do
        actionUpdateSlots[i] = false;
    end
end

local function ClearAllBuffSlots()
    for i = 1, MAX_BUFF_SLOT do
        playerBuffSlots[i]:Hide();
        playerDebuffSlots[i]:Hide();
        targetBuffSlots[i]:Hide();
        targetDebuffSlots[i]:Hide();
    end
    playerBuffSlots.index = 1;
    playerDebuffSlots.index = 1;
    targetBuffSlots.index = 1;
    targetDebuffSlots.index = 1;
end




-- Utility functions for checking buff

local function HasWeaponBuff()
    local mainHand, _, _, offHand, _, _ = GetWeaponEnchantInfo()
    return (mainHand ~= nil)
end

local function FindUnitBuff(unit, fn, buffname, checkMine)
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId = fn(unit, i);
        if (name == nil) then
            return;
        end
        if (checkMine and unitCaster ~= "player") then
            return;
        end
        if (name == buffname) then
            if (expirationTime) then
                expirationTime = expirationTime - GetTime()
            end
            return icon, count, duration, expirationTime;
        end
    end
    return nil;
end

local function PlayerBuff(buffname)
    return FindUnitBuff("player", UnitBuff, buffname, false);
end

local function PlayerDebuff(buffname)
    return FindUnitBuff("player", UnitDebuff, buffname, false);
end

local function TargetBuff(buffname)
    return FindUnitBuff("target", UnitBuff, buffname, true);
end

local function TargetDebuff(buffname)
    return FindUnitBuff("target", UnitDebuff, buffname, true);
end

-- Utility functions for updating slots

-- private

local function BuffKeep(func, slots, ...)
    for i, v in ipairs({...}) do
        if (type(v) == "table") then
            local hasBuff = false
            for i2, v2 in ipairs(v) do
                if (func(v2) ~= nil) then
                    hasBuff = true
                end
            end
            if (not hasBuff) then
--                DEFAULT_CHAT_FRAME:AddMessage(v[1]);
                slots:AddSlotTex(GetSpellTextureEx(v[1]));
            end
        elseif (v == "무기 버프") then
            if (not HasWeaponBuff()) then
                slots:AddSlotTex("Interface/Icons/Ability_Poisons");
            end
        elseif (func(v) == nil) then
--            DEFAULT_CHAT_FRAME:AddMessage(v);
            slots:AddSlotTex(GetSpellTextureEx(v));
        end
    end
end

-- public

local function PlayerBuffMissing(...)
    BuffKeep(PlayerBuff, playerBuffSlots, ...)
end

local function FriendBuffMissing(...)
    if (UnitExists("target") and (not UnitIsDead("target")) and UnitIsFriend("target", "player")) then
        BuffKeep(TargetBuff, targetBuffSlots, ...)
    end
end

local function EnemyDebuffMissing(...)
    if (UnitExists("target") and (not UnitIsDead("target")) and not UnitIsFriend("target", "player")) then
        BuffKeep(TargetDebuff, targetDebuffSlots, ...)
    end
end

local function PlayerBuffAlert(...)
    for i, v in ipairs({...}) do
        local icon, count, duration, timeLeft = PlayerBuff(v);
        if (icon ~= nil and timeLeft < 180) then
            playerBuffSlots:AddSlotBuff(PlayerBuff, v);
        end
    end
end

local function FriendBuffAlert(...)
    for i, v in ipairs({...}) do
        if (TargetBuff(v) ~= nil) then
            targetBuffSlots:AddSlotBuff(TargetBuff, v);
        end
    end
end

local function EnemyBuffAlert(...)
    for i, v in ipairs({...}) do
        if (UnitExists("target") and UnitIsEnemy("target", "player")) then
            local icon = TargetBuff(v);
            if (icon ~= nil) then
                targetBuffSlots:AddSlotTex(icon);
            end
        end
    end
end

local function EnemyDebuffAlert(...)
    for i, v in ipairs({...}) do
--        if (UnitExists("target") and UnitIsEnemy("target", "player")) then
        if (UnitExists("target")) then
            local icon = TargetDebuff(v);
            if (icon ~= nil) then
                targetDebuffSlots:AddSlotBuff(TargetDebuff, v);
            end
        end
    end
end

local function SpellReady(...)
    for i, v in ipairs({...}) do
--        if (UnitAffectingCombat("player") and enabled ~= 0 and start == 0) then
        if (UnitAffectingCombat("player")) then
            local start, duration, enabled = GetSpellCooldown(v);
            if (start == nil) then
                DEFAULT_CHAT_FRAME:AddMessage("SpellReady: ".. v);
            elseif (start == 0) then
                playerBuffSlots:AddSlotTex(GetSpellTextureEx(v));
            else
                local remain = start + duration - GetTime();
                if (remain <= 1) then -- global cooldown
                    playerBuffSlots:AddSlotTex(GetSpellTextureEx(v));
                end
            end
        end
    end
end

local function UpdateActionSlots(...)
    for i, v in ipairs({...}) do
        local start, duration, enabled = GetSpellCooldown(v);
        local cooldown = 0;
        if (start == nil) then
            return
        end
        if (start > 0 and duration > 0) then
            cooldown = start + duration - GetTime();
        end
        if (cooldown == 0) then
            actionUpdateSlots[i] = false;
        end
        if (cooldown > 1.5 or actionUpdateSlots[i]) then
            actionSlots[i]:SetCooldown(GetSpellTextureEx(v), math.ceil(cooldown));
            actionUpdateSlots[i] = true;
        else
            actionSlots[i]:SetCooldown(GetSpellTextureEx(v));
        end
        --DEFAULT_CHAT_FRAME:AddMessage("Width: " .. i .. ":" .. duration);
    end
end

local function PlayerSpellActivating()
    for k, v in pairs(activatedSpells) do
        if (v) then
            playerBuffSlots:AddSlotTex(GetSpellTextureEx(k));
        end
    end
end

-- Update loop
local prevTime = 0
local function OnUpdate()
    local time = GetTime()
    if (time - prevTime < 0.5) then
        return nil
    end

    local t1, t2, t3
    _, _, _, _, t1 = GetTalentTabInfo(1);
    _, _, _, _, t2 = GetTalentTabInfo(2);
    _, _, _, _, t3 = GetTalentTabInfo(3);

    ClearAllBuffSlots();

    if (UnitClass("player") == "주술사") then
        SpellReady("대지 충격")
        PlayerBuffAlert("집중", "질풍");
        PlayerBuffMissing("번개 보호막", "무기 버프")
 
    elseif (UnitClass("player") == "드루이드") then
        PlayerBuffAlert("정신 집중", "야생의 포효");
--        SpellReady("자연의 손아귀", "숨기");
        FriendBuffAlert("회복", "피어나는 생명", "재생");
        PlayerBuffMissing("가시", {"야생의 선물", "야생의 징표"});
--        PlayerBuffMissing("가시", {"야생의 선물", "야생의 징표"});
        EnemyBuffAlert("회피", "그림자 망토", "주문 반사");
        --EnemyDebuffMissing({"요정의 불꽃", "요정의 불꽃 (야성)"});
        EnemyDebuffAlert("짓이기기 (표범)");
        UpdateActionSlots("맹공격", "광폭화");

    elseif (UnitClass("player") == "사제") then
        if (t3 > 30) then -- 암흑
            PlayerBuffMissing({"내면의 열정", "내면의 의지"}, "신의 권능: 인내", "흡혈의 선물");
            EnemyDebuffAlert("파멸의 역병", "어둠의 권능: 고통", "흡혈의 손길");
            FriendBuffAlert("신의 권능: 보호막", "소생");
            UpdateActionSlots("어둠의 권능: 죽음", "정신 분열", "파멸의 역병", "어둠의 마귀", "희망의 찬가");
        else
            PlayerBuffAlert("우연한 행운");
            PlayerBuffMissing({"내면의 열정", "내면의 의지"}, "신의 권능: 인내", {"차크라: 평온", "차크라: 성역", "차크라: 응징"});
            EnemyDebuffAlert("파멸의 역병", "어둠의 권능: 고통");
            FriendBuffAlert("신의 권능: 보호막", "소생");
            UpdateActionSlots("어둠의 권능: 죽음", "신성한 불꽃", "신의 권능: 응징", "파멸의 역병", "어둠의 마귀", "희망의 찬가");
        end

    elseif (UnitClass("player") == "전사") then
        SpellReady("방패 밀쳐내기", "복수");
        PlayerBuffMissing("방패 막기", {"전투의 외침", "지휘의 외침"});
        EnemyDebuffMissing("천둥벼락", "사기의 외침", "방어구 가르기");

    elseif (UnitClass("player") == "성기사") then
        if (t2 > 30) then -- 보호
            PlayerBuffMissing("정의의 격노", {"기원의 오라", "응보의 오라", "집중의 오라", "화염 저항의 오라", "암흑 저항의 오라", "냉기 저항의 오라"}, {"상급 힘의 축복", "상급 지혜의 축복", "상급 구원의 축복", "상급 성역의 축복", "상급 왕의 축복", "상급 빛의 축복", "힘의 축복", "지혜의 축복", "구원의 축복", "성역의 축복", "왕의 축복", "빛의 축복"});
        elseif (t1 > 30) then -- 신성
            PlayerBuffAlert("빛 주입", "천상의 보호막", "봉화의 빛", "신의 계시", "빛의 은총", "정의의 격노");
            PlayerBuffMissing({"기원의 오라", "응보의 오라", "집중의 오라", "화염 저항의 오라", "암흑 저항의 오라", "냉기 저항의 오라"}, {"상급 힘의 축복", "상급 지혜의 축복", "상급 구원의 축복", "상급 성역의 축복", "상급 왕의 축복", "상급 빛의 축복", "힘의 축복", "지혜의 축복", "구원의 축복", "성역의 축복", "왕의 축복", "빛의 축복"});
            UpdateActionSlots("신성화", "신성 충격", "빛의 심판", "신의 계시", "신의 은총");
            FriendBuffAlert("빛의 봉화");
            EnemyDebuffAlert({"지혜의 심판", "빛의 심판"});
        else
            PlayerBuffAlert("전쟁의 기술", "천상의 보호막", "보호의 손길");
            PlayerBuffMissing({"지휘의 문장", "피의 문장"}, {"기원의 오라", "응보의 오라", "집중의 오라", "화염 저항의 오라", "암흑 저항의 오라", "냉기 저항의 오라", "고결의 오라"}, {"상급 힘의 축복", "상급 지혜의 축복", "상급 구원의 축복", "상급 성역의 축복", "상급 왕의 축복", "상급 빛의 축복", "힘의 축복", "지혜의 축복", "구원의 축복", "성역의 축복", "왕의 축복", "빛의 축복"});
            EnemyBuffAlert("회피", "그림자 망토", "주문 반사");
            EnemyDebuffAlert("심판의 망치", "참회");
            UpdateActionSlots("신성화", "성전사의 일격", "천상의 폭풍", "빛의 심판", "천벌의 망치", "심판의 망치", "참회");
        end
        --PlayerBuffAlert("빛의 은총");
        
    elseif (UnitClass("player") == "죽음의 기사") then
        if (t1 > 30) then -- 혈기 탱
            PlayerSpellActivating();
            PlayerBuffAlert("칼날 보호막", "뼈의 보호막", "흡혈", "춤추는 룬 무기", "얼음같은 인내력", "대마법 보호막");
            PlayerBuffMissing({"겨울의 뿔피리", "대지력"});
            UpdateActionSlots("정신 얼리기", "질식시키기", "돌발 열병", "죽음과 부패", "얼음같은 인내력", "대마법 보호막", "혈기 전환", "룬 무기 강화", "춤추는 룬 무기", "사자의 군대");
            --, "죽음의 손아귀", "어둠의 명령", "뼈의 보호막", "흡혈", "포세이큰의 의지", "죽음의 서약", "시체 되살리기", "시체 먹기", "대마법 지대"

            EnemyDebuffAlert("핏빛 열병", "어둠의 명령", "죽음의 손아귀", "서리 열병", "피의 역병", "얼음 결계");
            EnemyBuffAlert("회피", "그림자 망토", "주문 반사", "배고픔", "배부름", "격분", "출혈이 멈추지 않는 상처");

        elseif (t2 > 30) then -- 냉기 딜
            SpellReady("겨울의 뿔피리", "얼음 기둥", "혈기 전환");
            PlayerBuffAlert("도살기", "혹한의 안개", "부정의 힘", "얼음같은 인내력");
            EnemyDebuffAlert("어둠의 명령", "죽음의 손아귀", "서리 열병", "피의 역병", "얼음 결계");
            UpdateActionSlots("정신 얼리기", "질식시키기", "돌발 열병", "죽음과 부패", "얼음같은 인내력", "대마법 보호막", "룬 무기 강화", "사자의 군대");

        else -- 부정 딜
            PlayerSpellActivating();
            PlayerBuffAlert("얼음같은 인내력", "대마법 보호막", "파멸의 눈", "부정의 힘");
            PlayerBuffMissing({"겨울의 뿔피리", "대지력"}); --"뼈의 보호막",
            UpdateActionSlots("정신 얼리기", "질식시키기", "돌발 열병", "죽음과 부패", "얼음같은 인내력", "대마법 보호막", "혈기 전환", "룬 무기 강화", "가고일 부르기", "사자의 군대");
            --, "죽음의 손아귀", "어둠의 명령", "뼈의 보호막", "포세이큰의 의지", "죽음의 서약", "시체 되살리기", "시체 먹기", "대마법 지대"

            EnemyDebuffAlert("어둠의 명령", "죽음의 손아귀", "서리 열병", "피의 역병", "얼음 결계");
            EnemyBuffAlert("회피", "그림자 망토", "주문 반사");
        end

    elseif (UnitClass("player") == "도적") then
        PlayerBuffAlert("난도질");
    end

    prevTime = time
end

local function OnEvent(self, e, spellId)
    if (e == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") then
        activatedSpells[spellId] = true;
    elseif (e == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE") then
        activatedSpells[spellId] = false;
    end
end

-- Initialization

local f = CreateFrame("Frame", "BuffAlert");
f:SetPoint("CENTER", 0, 0);
f:SetWidth(100);
f:SetHeight(100);
f:SetScript("OnUpdate", OnUpdate);
f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW");
f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE");
f:SetScript("OnEvent", OnEvent);
f:Show()

debug = f:CreateFontString(nil, 0, "GameFontNormal");
debug:SetPoint("CENTER");

CreateAllSlots();
