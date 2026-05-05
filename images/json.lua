script_name('Rules by Runelli')
script_author('OpenAI')
script_version('0.9.1')  -- Без копирования, поиск в отдельной вкладке

require 'lib.moonloader'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local ffi = require 'ffi'
local inicfg = require 'inicfg'
local json = require 'json'

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local function cp1251(text) return u8:decode(text) end

local new = imgui.new

-- ===================== НАСТРОЙКИ =====================
local GITHUB_RAW_URL = "https://filedelete.github.io/arizona-rules/rules_data.json"
-- =====================================================

local window_state = new.bool(false)
local selected_category = 1
local selected_rule = 1
local style_applied = false
local pending_scroll_to_top = false
local active_tab = 0   -- 0 = просмотр, 1 = поиск

-- Поисковые переменные
local search_buffer = new.char[256]()
local search_status = ''
local active_highlight_query = ''
local active_match_block_index = nil
local active_match_label = ''
local search_results = {}
local active_search_result = 0

local is_binding_key = false
local bind_wait_frames = 0
local keybind_status = ''
local expanded_sections = {}
local section_anim = {}

local ini_name = 'rules_by_runelli'
local ini_template = { main = { open_key = 121, rules_version = '' } }
local settings = inicfg.load(ini_template, ini_name)
if not settings or not settings.main then settings = ini_template end
settings.main.open_key = tonumber(settings.main.open_key) or 121
inicfg.save(settings, ini_name)

local function toggleMenu()
    window_state[0] = not window_state[0]
end

-- HTTP
local requests = nil
local RULES = {}

-- ===================== ФУНКЦИИ ЗАГРУЗКИ =====================
local function loadRulesFromInternet()
    if not requests then
        sampAddChatMessage(cp1251("{FF0000}[Rules] Библиотека 'requests' не найдена."), -1)
        return false
    end
    sampAddChatMessage(cp1251("{66CCFF}[Rules] Загрузка правил из интернета..."), -1)
    local response = requests.get(GITHUB_RAW_URL, { timeout = 10 })
    local status_ok = false
    if response.status then
        if type(response.status) == 'number' and response.status == 200 then status_ok = true
        elseif type(response.status) == 'string' and response.status:find('200') then status_ok = true end
    elseif response.status_code and response.status_code == 200 then status_ok = true end
    if status_ok then
        local success, data = pcall(json.decode, response.text)
        if success and data and data.categories then
            for _, cat in ipairs(data.categories) do
                if not cat.rules then cat.rules = {} end
                for _, rule in ipairs(cat.rules) do
                    if not rule.blocks then rule.blocks = {} end
                end
            end
            RULES = data.categories
            sampAddChatMessage(cp1251("{66CCFF}[Rules] Загружено " .. #RULES .. " категорий."), -1)
            local new_version = data.version or data.last_update or ""
            if new_version ~= "" then
                local old_version = settings.main.rules_version or ""
                if old_version ~= new_version then
                    sampAddChatMessage(cp1251("{FFFF00}[Rules] ВНИМАНИЕ! Правила обновлены! Новая версия: " .. tostring(new_version)), -1)
                    settings.main.rules_version = new_version
                    inicfg.save(settings, ini_name)
                end
            end
            return true
        else
            sampAddChatMessage(cp1251("{FF0000}[Rules] Ошибка разбора JSON."), -1)
        end
    else
        local status_str = tostring(response.status or response.status_code or "неизвестно")
        if not status_str:find('200') then
            sampAddChatMessage(cp1251("{FF0000}[Rules] Ошибка HTTP " .. status_str), -1)
        end
    end
    return false
end

-- ===================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ =====================
local function color(r, g, b, a)
    return imgui.ImVec4(r / 255, g / 255, b / 255, a / 255)
end

local function toU32(col)
    if imgui.GetColorU32Vec4 then return imgui.GetColorU32Vec4(col) end
    if imgui.GetColorU32 then return imgui.GetColorU32(col) end
    return 0xFFFFFFFF
end

local COLORS = {
    text      = color(235, 235, 235, 255),
    gray      = color(175, 180, 190, 255),
    accent    = color(130, 180, 255, 255),
    warn      = color(255, 120, 90, 255),
    gold      = color(255, 210, 110, 255),
    title     = color(245, 248, 255, 255),
    menu      = color(220, 225, 235, 255),
    selected  = color(140, 190, 255, 255),
    highlight = color(255, 235, 140, 255),
    success   = color(115, 220, 140, 255),
    danger    = color(255, 105, 105, 255),
    info      = color(105, 205, 255, 255),
    purple    = color(195, 155, 255, 255),
    orange    = color(255, 175, 100, 255),

    section_admin     = color(185, 145, 255, 255),
    section_main      = color(130, 180, 255, 255),
    section_events    = color(255, 170, 95, 255),
    section_state     = color(90, 220, 255, 255),
    section_illegal   = color(255, 110, 110, 255),

    card_fill         = color(255, 255, 255, 10),
    card_border       = color(95, 125, 180, 65),
    card_header_fill  = color(255, 255, 255, 14),
    card_header_border= color(120, 150, 205, 105),
    card_highlight_fill = color(255, 235, 140, 18),
    card_highlight_border = color(255, 215, 110, 180),

    bg1       = color(9, 12, 22, 240),
    bg2       = color(18, 22, 38, 240),
    bg3       = color(28, 18, 46, 240),
    panel1    = color(14, 18, 30, 225),
    panel2    = color(24, 28, 46, 225),
    border    = color(90, 120, 180, 130)
}

local RU_CASE_MAP = {
    ['А']='а', ['Б']='б', ['В']='в', ['Г']='г', ['Д']='д', ['Е']='е', ['Ё']='ё',
    ['Ж']='ж', ['З']='з', ['И']='и', ['Й']='й', ['К']='к', ['Л']='л', ['М']='м',
    ['Н']='н', ['О']='о', ['П']='п', ['Р']='р', ['С']='с', ['Т']='т', ['У']='у',
    ['Ф']='ф', ['Х']='х', ['Ц']='ц', ['Ч']='ч', ['Ш']='ш', ['Щ']='щ', ['Ъ']='ъ',
    ['Ы']='ы', ['Ь']='ь', ['Э']='э', ['Ю']='ю', ['Я']='я'
}

local INLINE_MARKERS = {
    { token = 'Наказание:',  color = 'warn'   },
    { token = 'Примечание:', color = 'warn'   },
    { token = 'Пример:',     color = 'gold'   },
    { token = 'Исключение:', color = 'accent' },
    { token = 'Дополнение:', color = 'warn'   }
}

local function getCurrentRule()
    local cat = RULES[selected_category]
    if not cat then return nil end
    return cat.rules[selected_rule]
end

local function resetRuleIndexIfNeeded()
    local cat = RULES[selected_category]
    if cat and selected_rule > #cat.rules then selected_rule = 1 end
end

local function getColorByName(name)
    return COLORS[name] or COLORS.text
end

local function normalizeText(text)
    text = tostring(text or '')
    text = text:gsub('→', ' - '):gsub('➜', ' - '):gsub('➡', ' - '):gsub('➝', ' - '):gsub('⟶', ' - ')
    return text
end

local function makeSearchKey(text)
    local s = normalizeText(text)
    s = string.lower(s)
    for upper, lower in pairs(RU_CASE_MAP) do s = s:gsub(upper, lower) end
    return s
end

local function openUrl(url)
    if url and url ~= '' then os.execute('start "" "' .. url .. '"') end
end

local function getSearchText()
    return ffi.string(search_buffer)
end

local function getCategoryAccent(category)
    if not category then return COLORS.accent end
    local title = tostring(category.title or '')
    if title == 'АДМИН-РАЗДЕЛ' then return COLORS.section_admin
    elseif title == 'Основные правила серверов' then return COLORS.section_main
    elseif title == 'Правила серверных мероприятий' then return COLORS.section_events
    elseif title == 'Правила для государственных организаций' then return COLORS.section_state
    elseif title == 'Правила для нелегальных организаций' then return COLORS.section_illegal
    end
    return COLORS.accent
end

local function getSubtitleColor(text)
    local key = makeSearchKey(text or '')
    if key:find('запрещ') or key:find('штраф') then return COLORS.warn
    elseif key:find('разреш') then return COLORS.success
    elseif key:find('видео') or key:find('опроверж') then return COLORS.info
    elseif key:find('минималь') then return COLORS.purple
    elseif key:find('дополнитель') or key:find('условия') or key:find('общее') then return COLORS.orange
    end
    return COLORS.warn
end

local function getCurrentPathText()
    local cat = RULES[selected_category]
    local rule = getCurrentRule()
    if not cat or not rule then return '' end
    return tostring(cat.title) .. '  >  ' .. tostring(rule.title)
end

local function getSourceLabel(url)
    local s = tostring(url or '')
    s = s:gsub('^https?://', ''):gsub('/$', '')
    return s
end

-- ===================== БЕЗ КОПИРОВАНИЯ =====================

local function setAllSectionsExpanded(value)
    for i = 1, #RULES do
        expanded_sections[i] = value
        section_anim[i] = value and 1 or 0
    end
end

local function selectRule(catIdx, ruleIdx)
    selected_category = catIdx
    selected_rule = ruleIdx
    resetRuleIndexIfNeeded()
    pending_scroll_to_top = true
    expanded_sections[catIdx] = true
end

local function getFlatRuleList()
    local flat = {}
    for ci, cat in ipairs(RULES) do
        for ri, _ in ipairs(cat.rules or {}) do
            table.insert(flat, { category_index = ci, rule_index = ri })
        end
    end
    return flat
end

local function goToRelativeRule(offset)
    local flat = getFlatRuleList()
    if #flat == 0 then return end
    local current = 1
    for i, item in ipairs(flat) do
        if item.category_index == selected_category and item.rule_index == selected_rule then
            current = i
            break
        end
    end
    local target = math.min(#flat, math.max(1, current + offset))
    local item = flat[target]
    if item then selectRule(item.category_index, item.rule_index) end
end

-- Обновлённая функция поиска (сохраняет результаты в глобальные переменные)
local function runSearch()
    local query = normalizeText(getSearchText())
    local qKey = makeSearchKey(query)
    search_results = {}
    active_search_result = 0
    active_match_block_index = nil
    active_match_label = ''
    active_highlight_query = ''
    if qKey == '' then
        search_status = 'Введите текст'
        return
    end
    for ci, cat in ipairs(RULES) do
        for ri, rule in ipairs(cat.rules or {}) do
            if makeSearchKey(rule.title):find(qKey, 1, true) then
                table.insert(search_results, { category_index = ci, rule_index = ri, block_index = nil, block_label = rule.title })
            end
            for bi, blk in ipairs(rule.blocks or {}) do
                -- собираем текст блока для поиска
                local parts = {}
                if blk.label then table.insert(parts, normalizeText(blk.label)) end
                if blk.text then table.insert(parts, normalizeText(blk.text)) end
                if blk.link then table.insert(parts, normalizeText(blk.link)) end
                if blk.type then table.insert(parts, normalizeText(blk.type)) end
                local haystack = table.concat(parts, ' ')
                if makeSearchKey(haystack):find(qKey, 1, true) then
                    local label = blk.label or blk.text or rule.title
                    table.insert(search_results, { category_index = ci, rule_index = ri, block_index = bi, block_label = label })
                end
            end
        end
    end
    if #search_results == 0 then
        search_status = 'Ничего не найдено'
    else
        search_status = 'Найдено: ' .. #search_results
        active_search_result = 1
        -- Автоматически применяем первый результат и переключаем вкладку
        applySearchResult(1)
        active_tab = 0   -- переключаемся на просмотр, чтобы сразу показать правило
    end
end

local function clearSearch()
    ffi.fill(search_buffer, ffi.sizeof(search_buffer), 0)
    search_status = ''
    active_highlight_query = ''
    active_match_block_index = nil
    active_match_label = ''
    search_results = {}
    active_search_result = 0
end

local function applySearchResult(idx)
    local res = search_results[idx]
    if not res then return end
    active_search_result = idx
    selected_category = res.category_index
    selected_rule = res.rule_index
    active_match_block_index = res.block_index
    active_match_label = res.block_label or ''
    active_highlight_query = normalizeText(getSearchText())
    pending_scroll_to_top = true
    -- переключаем на вкладку просмотра
    active_tab = 0
end

-- ===================== ОТРИСОВКА КОНТЕНТА =====================
local function renderCardContainer(renderer, opts)
    opts = opts or {}
    local draw = imgui.GetWindowDrawList()
    local useChannels = draw and draw.ChannelsSplit and pcall(function() draw:ChannelsSplit(2) draw:ChannelsSetCurrent(1) end)
    local startScreen = imgui.GetCursorScreenPos()
    local startCursorX = imgui.GetCursorPosX()
    local fullWidth = imgui.GetContentRegionAvail().x
    imgui.BeginGroup()
    renderer()
    imgui.EndGroup()
    local min = imgui.GetItemRectMin()
    local max = imgui.GetItemRectMax()
    local padX, padY = opts.pad_x or 8, opts.pad_y or 6
    local rounding = opts.rounding or 8
    local cardMinX = math.min(min.x, startScreen.x)
    local cardMaxX = math.max(max.x, startScreen.x + fullWidth)
    local pMin = imgui.ImVec2(cardMinX - padX, min.y - padY)
    local pMax = imgui.ImVec2(cardMaxX + padX, max.y + padY)
    if useChannels then draw:ChannelsSetCurrent(0) end
    draw:AddRectFilled(pMin, pMax, toU32(opts.fill or COLORS.card_fill), rounding)
    draw:AddRect(pMin, pMax, toU32(opts.border or COLORS.card_border), rounding, 0, 1.0)
    if opts.marker then
        draw:AddRectFilled(imgui.ImVec2(pMin.x + 2, pMin.y + 2), imgui.ImVec2(pMin.x + 5, pMax.y - 2), toU32(opts.marker), 4.0)
    end
    if useChannels then draw:ChannelsSetCurrent(1) draw:ChannelsMerge() end
    imgui.SetCursorPosX(startCursorX)
    imgui.Dummy(imgui.ImVec2(0, opts.after_spacing or 4))
end

local function keycodeToName(code)
    code = tonumber(code) or 0
    if code >= 65 and code <= 90 then return string.char(code) end
    if code >= 48 and code <= 57 then return string.char(code) end
    if code >= 96 and code <= 105 then return 'NUM ' .. tostring(code - 96) end
    if code >= 112 and code <= 123 then return 'F' .. tostring(code - 111) end
    local names = {[8]='BACKSPACE',[9]='TAB',[13]='ENTER',[16]='SHIFT',[17]='CTRL',[18]='ALT',[19]='PAUSE',[20]='CAPSLOCK',
        [27]='ESC',[32]='SPACE',[33]='PAGEUP',[34]='PAGEDOWN',[35]='END',[36]='HOME',[37]='LEFT',[38]='UP',[39]='RIGHT',
        [40]='DOWN',[45]='INSERT',[46]='DELETE',[91]='LWIN',[92]='RWIN',[106]='NUM *',[107]='NUM +',[109]='NUM -',
        [110]='NUM .',[111]='NUM /',[144]='NUMLOCK',[145]='SCROLLLOCK',[186]=';',[187]='=',[188]=',',[189]='-',[190]='.',
        [191]='/',[192]='`',[219]='[',[220]='\\',[221]=']',[222]="'"}
    return names[code] or tostring(code)
end

local function isBindableKey(vk)
    if not vk then return false end
    if vk >= 1 and vk <= 6 then return false end
    return vk >= 8 and vk <= 222
end

local function getPressedBindKey()
    for vk = 1, 222 do if wasKeyPressed(vk) then return vk end end
    return nil
end

local function pushSegment(segments, text, color_name, scale)
    if not text or text == '' then return end
    local col = getColorByName(color_name)
    local sc = scale or 1.0
    local last = segments[#segments]
    if last and last.color == col and last.scale == sc then
        last.text = last.text .. text
        return
    end
    table.insert(segments, { text = text, color = col, scale = sc })
end

local function splitStyledSegments(text, defaultColorName)
    text = normalizeText(text)
    local segments, pos = {}, 1
    while pos <= #text do
        local bestStart, bestEnd, bestMarker
        for _, m in ipairs(INLINE_MARKERS) do
            local s, e = text:find(m.token, pos, true)
            if s and (not bestStart or s < bestStart) then bestStart, bestEnd, bestMarker = s, e, m end
        end
        if not bestStart then
            pushSegment(segments, text:sub(pos), defaultColorName, 1.0)
            break
        end
        if bestStart > pos then pushSegment(segments, text:sub(pos, bestStart - 1), defaultColorName, 1.0) end
        pushSegment(segments, text:sub(bestStart, bestEnd), bestMarker.color, 1.0)
        pos = bestEnd + 1
    end
    return segments
end

local function splitHighlightParts(text, query)
    local original, queryText = tostring(text or ''), tostring(query or '')
    local parts = {}
    if queryText == '' then return { { text = original, highlighted = false } } end
    local origKey, qKey = makeSearchKey(original), makeSearchKey(queryText)
    local pos = 1
    while pos <= #origKey do
        local s, e = origKey:find(qKey, pos, true)
        if not s then
            table.insert(parts, { text = original:sub(pos), highlighted = false })
            break
        end
        if s > pos then table.insert(parts, { text = original:sub(pos, s - 1), highlighted = false }) end
        table.insert(parts, { text = original:sub(s, e), highlighted = true })
        pos = e + 1
    end
    return parts
end

local function buildRenderableParts(segments, highlightQuery)
    local parts = {}
    for _, seg in ipairs(segments) do
        local text = normalizeText(seg.text or '')
        local sub = splitHighlightParts(text, highlightQuery)
        for _, p in ipairs(sub) do
            table.insert(parts, { text = p.text, color = p.highlighted and COLORS.highlight or seg.color, scale = 1.0 })
        end
    end
    return parts
end

local function wrapStyledParts(parts, maxWidth)
    local lines, curLine, curWidth = {}, {}, 0
    local function pushLine() table.insert(lines, curLine); curLine = {}; curWidth = 0 end
    local function addToken(tokenText, tokenColor, tokenScale)
        if tokenText == '' then return end
        local scale = tokenScale or 1.0
        local w = imgui.CalcTextSize(tokenText).x * scale
        if curWidth > 0 and curWidth + w > maxWidth then pushLine() end
        table.insert(curLine, { text = tokenText, color = tokenColor, scale = scale })
        curWidth = curWidth + w
    end
    for _, part in ipairs(parts) do
        local text, color, scale = part.text or '', part.color, part.scale or 1.0
        local start = 1
        while start <= #text do
            local nl = text:find('\n', start, true)
            local piece = nl and text:sub(start, nl - 1) or text:sub(start)
            if piece ~= '' then
                local pos = 1
                while pos <= #piece do
                    local s, e = piece:find('%s*%S+', pos)
                    if not s then
                        local tail = piece:sub(pos)
                        if tail ~= '' then addToken(tail, color, scale) end
                        break
                    end
                    if s > pos then addToken(piece:sub(pos, s - 1), color, scale) end
                    local token = piece:sub(s, e)
                    local nxt = e + 1
                    while nxt <= #piece and piece:sub(nxt, nxt):match('%s') do token = token .. piece:sub(nxt, nxt); nxt = nxt + 1 end
                    addToken(token, color, scale)
                    pos = nxt
                end
            end
            if nl then pushLine(); start = nl + 1 else break end
        end
    end
    if #curLine > 0 then pushLine() end
    if #lines == 0 then lines[1] = {} end
    return lines
end

local function appendSegments(dst, src)
    for _, seg in ipairs(src) do table.insert(dst, seg) end
end

local function renderWrappedSegments(segments, indent)
    indent = indent or 0
    local hl = normalizeText(active_highlight_query or '')
    local parts = buildRenderableParts(segments, hl)
    local baseX = imgui.GetCursorPosX() + indent
    local avail = imgui.GetContentRegionAvail().x - indent
    if avail < 50 then avail = imgui.GetContentRegionAvail().x end
    local lines = wrapStyledParts(parts, avail)
    for _, line in ipairs(lines) do
        imgui.SetCursorPosX(baseX)
        if #line == 0 then
            imgui.Dummy(imgui.ImVec2(0, imgui.GetTextLineHeight()))
        else
            local first = true
            for _, ch in ipairs(line) do
                if not first then imgui.SameLine(0, 0) end
                imgui.PushStyleColor(imgui.Col.Text, ch.color)
                imgui.TextUnformatted(ch.text)
                imgui.PopStyleColor()
                first = false
            end
        end
    end
end

local function renderStyledText(text, defaultColor)
    local seg = splitStyledSegments(text, defaultColor or 'text')
    renderWrappedSegments(seg, 0)
end

local function renderRuleLine(label, text, indent)
    local seg = { { text = normalizeText(label) .. ' ', color = COLORS.gold, scale = 1.0 } }
    appendSegments(seg, splitStyledSegments(text, 'text'))
    renderWrappedSegments(seg, indent or 0)
end

local function renderTermLine(label, text)
    local seg = {
        { text = '• ', color = COLORS.text, scale = 1.0 },
        { text = normalizeText(label), color = COLORS.gold, scale = 1.0 },
        { text = ' - ', color = COLORS.text, scale = 1.0 }
    }
    appendSegments(seg, splitStyledSegments(text, 'text'))
    renderWrappedSegments(seg, 0)
end

local function renderLabeledLine(label, labelColor, text, indent)
    local seg = {}
    if label and label ~= '' then
        table.insert(seg, { text = normalizeText(label), color = labelColor, scale = 1.0 })
        table.insert(seg, { text = ' ', color = COLORS.text, scale = 1.0 })
    end
    appendSegments(seg, splitStyledSegments(text, 'text'))
    renderWrappedSegments(seg, indent or 0)
end

local function renderBulletLine(text, bulletColor, indent)
    local seg = { { text = '• ', color = bulletColor, scale = 1.0 } }
    appendSegments(seg, splitStyledSegments(text, 'text'))
    renderWrappedSegments(seg, indent or 14)
end

local function renderBlock(block, blockIndex)
    local isMatch = active_match_block_index and blockIndex == active_match_block_index
    local function content()
        if block.type == 'link_button' then
            if imgui.SmallButton(block.text or 'Открыть ссылку') then openUrl(block.link) end
            return
        end
        if block.type == 'space' then imgui.Spacing(); return end
        if block.type == 'line' then imgui.Separator(); return end
        if block.type == 'title' then
            if block.centered then renderCenteredTextLine(block.text, COLORS.title, 1.12)
            else imgui.PushStyleColor(imgui.Col.Text, COLORS.title); imgui.SetWindowFontScale(1.12);
                 imgui.TextWrapped(normalizeText(block.text)); imgui.SetWindowFontScale(1.0); imgui.PopStyleColor() end
            return
        end
        if block.type == 'subtitle' then
            local col = getSubtitleColor(block.text)
            if block.centered then renderCenteredTextLine(block.text, col, 1.06)
            else imgui.PushStyleColor(imgui.Col.Text, col); imgui.SetWindowFontScale(1.06);
                 imgui.TextWrapped(normalizeText(block.text)); imgui.SetWindowFontScale(1.0); imgui.PopStyleColor() end
            return
        end
        if block.type == 'text' then renderStyledText(block.text, 'text'); return end
        if block.type == 'gray' then renderStyledText(block.text, 'gray'); return end
        if block.type == 'accent' then renderStyledText(block.text, 'accent'); return end
        if block.type == 'warn' then renderStyledText(block.text, 'warn'); return end
        if block.type == 'gold' then renderStyledText(block.text, 'gold'); return end
        if block.type == 'rule' then renderRuleLine(block.label or '', block.text or '', 0); return end
        if block.type == 'subrule' then renderRuleLine(block.label or '', block.text or '', 14); return end
        if block.type == 'labelline' then
            renderLabeledLine(block.label or '', getColorByName(block.color), block.text or '', block.indent or 0)
            return
        end
        if block.type == 'bullet' then
            renderBulletLine(block.text or '', getColorByName(block.bullet_color), block.indent or 14)
            return
        end
        if block.type == 'term' then renderTermLine(block.label or '', block.text or ''); return end
        if block.type == 'term_note' then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + 18)
            renderStyledText(block.text or '', 'gray')
            return
        end
    end
    if block.type == 'space' or block.type == 'line' then content(); return end
    content()
    local draw = imgui.GetWindowDrawList()
    local min = imgui.GetItemRectMin()
    local max = imgui.GetItemRectMax()
    if isMatch then
        draw:AddRect(imgui.ImVec2(min.x - 6, min.y - 3), imgui.ImVec2(max.x + 6, max.y + 3), toU32(COLORS.highlight), 5.0, 0, 1.0)
    end
    if block.type == 'title' or block.type == 'subtitle' then imgui.Dummy(imgui.ImVec2(0, 4))
    elseif block.type == 'link_button' then imgui.Dummy(imgui.ImVec2(0, 4))
    else imgui.Dummy(imgui.ImVec2(0, 2)) end
end

local function renderCenteredTextLine(text, colorVal, fontScale)
    local norm = normalizeText(text)
    local avail = imgui.GetContentRegionAvail().x
    local scale = fontScale or 1.0
    local tx = imgui.CalcTextSize(norm).x * scale
    imgui.PushStyleColor(imgui.Col.Text, colorVal or COLORS.text)
    imgui.SetWindowFontScale(scale)
    if tx <= avail then
        local baseX = imgui.GetCursorPosX()
        imgui.SetCursorPosX(baseX + math.max(0, (avail - tx) / 2))
        imgui.TextUnformatted(norm)
    else
        imgui.TextWrapped(norm)
    end
    imgui.SetWindowFontScale(1.0)
    imgui.PopStyleColor()
end

local function renderRuleTreeNode(catIdx, ruleIdx, rule, isSelected, accent, anim)
    local style = imgui.GetStyle()
    local oldAlpha = style.Alpha
    style.Alpha = oldAlpha * math.max(0.45, anim or 1.0)
    local shift = math.floor((1.0 - (anim or 1.0)) * 10)
    if shift > 0 then imgui.SetCursorPosX(imgui.GetCursorPosX() + shift) end
    imgui.SetCursorPosX(imgui.GetCursorPosX() + 6)
    local label = rule.title .. '##rule_' .. catIdx .. '_' .. ruleIdx
    if imgui.Selectable(label, isSelected) then selectRule(catIdx, ruleIdx) end
    local draw = imgui.GetWindowDrawList()
    local min = imgui.GetItemRectMin()
    local max = imgui.GetItemRectMax()
    draw:AddRectFilled(imgui.ImVec2(min.x+1, min.y+3), imgui.ImVec2(min.x+4, max.y-3), toU32(isSelected and accent or COLORS.border), 3.0)
    if isSelected then draw:AddRect(imgui.ImVec2(min.x+1, min.y+1), imgui.ImVec2(max.x-1, max.y-1), toU32(accent), 6.0, 0, 1.0) end
    style.Alpha = oldAlpha
end

local function renderLeftMenu()
    imgui.PushStyleColor(imgui.Col.Text, COLORS.menu); imgui.SetWindowFontScale(1.04); imgui.Text('Разделы'); imgui.SetWindowFontScale(1.0); imgui.PopStyleColor()
    imgui.Separator()
    for ci, cat in ipairs(RULES) do
        local accent = getCategoryAccent(cat)
        if expanded_sections[ci] == nil then expanded_sections[ci] = (ci == selected_category); section_anim[ci] = expanded_sections[ci] and 1 or 0 end
        if imgui.SetNextItemOpen then imgui.SetNextItemOpen(expanded_sections[ci], imgui.Cond.Always) end
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 6)
        imgui.PushStyleColor(imgui.Col.Text, accent)
        local opened = imgui.TreeNodeStr(cat.title)
        imgui.PopStyleColor()
        expanded_sections[ci] = opened
        section_anim[ci] = (section_anim[ci] or (opened and 1 or 0)) + (((opened and 1 or 0) - (section_anim[ci] or 0)) * 0.28)
        local draw = imgui.GetWindowDrawList()
        local min = imgui.GetItemRectMin()
        local max = imgui.GetItemRectMax()
        draw:AddRectFilled(imgui.ImVec2(min.x+1, min.y+3), imgui.ImVec2(min.x+4, max.y-3), toU32(accent), 3.0)
        if imgui.IsItemClicked() then selected_category = ci; selected_rule = math.min(selected_rule, #(cat.rules or {})); if selected_rule < 1 then selected_rule = 1 end; pending_scroll_to_top = true end
        if opened then
            for ri, rule in ipairs(cat.rules or {}) do
                local isSel = (selected_category == ci and selected_rule == ri)
                renderRuleTreeNode(ci, ri, rule, isSel, accent, section_anim[ci])
            end
            imgui.TreePop()
        end
    end
end

local function renderSearchResultsTab()
    -- Поле ввода
    local inputWidth = imgui.GetContentRegionAvail().x - 110
    if inputWidth < 120 then inputWidth = 120 end
    local enterFlag = 0
    if imgui.InputTextFlags and imgui.InputTextFlags.EnterReturnsTrue then enterFlag = imgui.InputTextFlags.EnterReturnsTrue end
    imgui.PushItemWidth(inputWidth)
    local enterPressed = imgui.InputText('##search_input', search_buffer, ffi.sizeof(search_buffer), enterFlag)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Найти', imgui.ImVec2(50,0)) then runSearch() end
    imgui.SameLine()
    if imgui.Button('Сброс', imgui.ImVec2(52,0)) then clearSearch() end
    if enterPressed then runSearch() end

    if search_status ~= '' then
        imgui.PushStyleColor(imgui.Col.Text, COLORS.highlight)
        imgui.TextWrapped(search_status)
        imgui.PopStyleColor()
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    if #search_results > 0 then
        imgui.BeginChild('##search_results_list', imgui.ImVec2(0, 0), true)
        for i, res in ipairs(search_results) do
            local cat = RULES[res.category_index]
            if cat then
                local rule = cat.rules[res.rule_index]
                if rule then
                    local show_text = rule.title
                    if res.block_label and res.block_label ~= '' and res.block_label ~= rule.title then
                        show_text = show_text .. ' › ' .. res.block_label
                    end
                    if imgui.Selectable(show_text .. '##search_res_' .. i, active_search_result == i) then
                        applySearchResult(i)
                    end
                end
            end
        end
        imgui.EndChild()
    else
        imgui.TextWrapped('Введите текст для поиска или нажмите "Найти"')
    end

    imgui.Spacing()
end

-- Функция отображения вкладки просмотра правил
local function renderViewTab()
    local curCat = RULES[selected_category]
    local curRule = getCurrentRule()
    local footerH = 56
    local contH = imgui.GetContentRegionAvail().y
    if contH < 80 then contH = 80 end
    imgui.BeginChild('##rule_content', imgui.ImVec2(0, contH - footerH), false)
    if pending_scroll_to_top then
        imgui.SetScrollY(0)
        pending_scroll_to_top = false
    end
    if curCat and curRule then
        local hasMatch = false
        if active_search_result > 0 and active_match_block_index then
            hasMatch = true
        end
        renderCardContainer(function()
            for bi, blk in ipairs(curRule.blocks or {}) do
                renderBlock(blk, bi)
            end
        end, {
            fill = hasMatch and COLORS.card_highlight_fill or COLORS.card_fill,
            border = hasMatch and COLORS.card_highlight_border or getCategoryAccent(curCat),
            marker = hasMatch and COLORS.highlight or getCategoryAccent(curCat),
            pad_x = 10, pad_y = 8, after_spacing = 0
        })
    else
        imgui.Text('Нет данных для отображения. Проверьте интернет-соединение.')
    end
    imgui.EndChild()
    imgui.Spacing()
    renderFooterActions(curCat, curRule)
end

local function renderFooterActions(category, rule)
    if not category or not rule then return end
    renderCardContainer(function()
        if imgui.Button('Назад', imgui.ImVec2(80,0)) then goToRelativeRule(-1) end
        imgui.SameLine()
        if imgui.Button('Вперёд', imgui.ImVec2(80,0)) then goToRelativeRule(1) end
        imgui.SameLine()
        if imgui.Button('Открыть тему##footer', imgui.ImVec2(110,0)) then if rule and rule.link then openUrl(rule.link) end end
        imgui.SameLine()
        if imgui.Button('Свернуть всё', imgui.ImVec2(115,0)) then setAllSectionsExpanded(false) end
        imgui.SameLine()
        if imgui.Button('Развернуть всё', imgui.ImVec2(120,0)) then setAllSectionsExpanded(true) end
        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Text, COLORS.gray); imgui.Text('ЛКМ по строке - копировать (ВНИМАНИЕ: отключено)'); imgui.PopStyleColor()
    end, {
        fill = COLORS.card_header_fill,
        border = getCategoryAccent(category),
        marker = getCategoryAccent(category),
        pad_x = 8, pad_y = 6, after_spacing = 0
    })
end

local function renderRuleHeaderCard(category, rule)
    if not category or not rule then return end
    local accent = getCategoryAccent(category)
    local isHeadMatch = (active_search_result > 0 and active_match_block_index == nil)
    renderCardContainer(function()
        imgui.PushStyleColor(imgui.Col.Text, COLORS.gray); imgui.TextWrapped(getCurrentPathText()); imgui.PopStyleColor()
        imgui.PushStyleColor(imgui.Col.Text, COLORS.title); imgui.SetWindowFontScale(1.10); imgui.TextWrapped(rule.title); imgui.SetWindowFontScale(1.0); imgui.PopStyleColor()
        imgui.PushStyleColor(imgui.Col.Text, COLORS.gray); imgui.TextWrapped('Источник: ' .. getSourceLabel(rule.link)); imgui.PopStyleColor()
        if rule.link and rule.link ~= '' then if imgui.Button('Открыть тему', imgui.ImVec2(110,0)) then openUrl(rule.link) end end
    end, {
        fill = isHeadMatch and COLORS.card_highlight_fill or COLORS.card_header_fill,
        border = isHeadMatch and COLORS.card_highlight_border or accent,
        marker = isHeadMatch and COLORS.highlight or accent,
        pad_x = 10, pad_y = 8, after_spacing = 8
    })
end

local function renderKeybindPanel()
    imgui.PushStyleColor(imgui.Col.Text, COLORS.menu); imgui.Text('Клавиша открытия'); imgui.PopStyleColor()
    imgui.PushStyleColor(imgui.Col.Text, COLORS.gray); imgui.Text('Текущая клавиша: ' .. keycodeToName(settings.main.open_key)); imgui.PopStyleColor()
    if not is_binding_key then
        if imgui.Button('Назначить клавишу', imgui.ImVec2(150,0)) then is_binding_key = true; bind_wait_frames = 8; keybind_status = 'Нажмите любую клавишу... ESC - отмена' end
    else
        imgui.PushStyleColor(imgui.Col.Text, COLORS.highlight); imgui.Text('Ожидание нажатия...'); imgui.PopStyleColor()
        if imgui.Button('Отмена', imgui.ImVec2(90,0)) then is_binding_key = false; bind_wait_frames = 0; keybind_status = 'Отменено' end
    end
    if imgui.Button('Сбросить на F10', imgui.ImVec2(150,0)) then settings.main.open_key = 121; inicfg.save(settings, ini_name); keybind_status = 'Сброшено на F10' end
    if keybind_status ~= '' then imgui.PushStyleColor(imgui.Col.Text, COLORS.highlight); imgui.TextWrapped(keybind_status); imgui.PopStyleColor() end
end

local function drawGradientRect(draw_list, p_min, p_max, c1, c2, c3, c4)
    draw_list:AddRectFilledMultiColor(p_min, p_max, toU32(c1), toU32(c2), toU32(c3), toU32(c4))
end

local function beginGradientChild(id, size, border)
    local avail = imgui.GetContentRegionAvail()
    local fin = imgui.ImVec2(size.x <= 0 and avail.x or size.x, size.y <= 0 and avail.y or size.y)
    local pos = imgui.GetCursorScreenPos()
    local draw = imgui.GetWindowDrawList()
    local p2 = imgui.ImVec2(pos.x + fin.x, pos.y + fin.y)
    drawGradientRect(draw, pos, p2, COLORS.panel1, COLORS.panel2, COLORS.panel2, COLORS.panel1)
    draw:AddRect(pos, p2, toU32(COLORS.border), 8.0)
    imgui.BeginChild(id, fin, border)
end

local function applyStyle()
    local style = imgui.GetStyle()
    style.WindowPadding = imgui.ImVec2(10,10)
    style.FramePadding = imgui.ImVec2(8,6)
    style.ItemSpacing = imgui.ImVec2(8,6)
    style.ItemInnerSpacing = imgui.ImVec2(6,4)
    style.ScrollbarSize = 10
    style.WindowRounding = 8
    style.ChildRounding = 8
    style.FrameRounding = 6
    style.GrabRounding = 6
    style.Colors[imgui.Col.WindowBg] = color(0,0,0,0)
    if imgui.Col.ChildBg then style.Colors[imgui.Col.ChildBg] = color(0,0,0,0) elseif imgui.Col.ChildWindowBg then style.Colors[imgui.Col.ChildWindowBg] = color(0,0,0,0) end
    style.Colors[imgui.Col.Border] = color(90,120,180,110)
    style.Colors[imgui.Col.Text] = COLORS.text
    style.Colors[imgui.Col.Button] = color(40,55,85,180)
    style.Colors[imgui.Col.ButtonHovered] = color(60,85,130,220)
    style.Colors[imgui.Col.ButtonActive] = color(75,105,160,255)
    style.Colors[imgui.Col.Header] = color(45,65,100,180)
    style.Colors[imgui.Col.HeaderHovered] = color(60,90,140,220)
    style.Colors[imgui.Col.HeaderActive] = color(70,105,165,255)
    style.Colors[imgui.Col.Separator] = color(100,130,185,110)
    style.Colors[imgui.Col.ScrollbarBg] = color(15,18,28,140)
    style.Colors[imgui.Col.ScrollbarGrab] = color(70,90,125,170)
    style.Colors[imgui.Col.ScrollbarGrabHovered] = color(95,120,165,210)
    style.Colors[imgui.Col.ScrollbarGrabActive] = color(110,145,200,255)
end

function main()
    repeat wait(0) until isSampAvailable()
    
    local http_ok, req = pcall(require, 'requests')
    if not http_ok then
        sampAddChatMessage(cp1251("{FF0000}[Rules] Библиотека 'requests' не найдена. Скрипт не может загрузить правила."), -1)
    else
        requests = req
        loadRulesFromInternet()
    end
    
    if #RULES == 0 then
        sampAddChatMessage(cp1251("{FF0000}[Rules] Не удалось загрузить правила. Проверьте интернет и ссылку."), -1)
    end
    
    sampRegisterChatCommand('rulesui', toggleMenu)
    sampAddChatMessage(cp1251('{66CCFF}[Rules by Runelli]{FFFFFF} Открыть меню: /rulesui или горячей клавишей.'), -1)
    
    while true do
        wait(0)
        if not sampIsChatInputActive() and not isPauseMenuActive() then
            if is_binding_key then
                if bind_wait_frames > 0 then
                    bind_wait_frames = bind_wait_frames - 1
                else
                    local pressed = getPressedBindKey()
                    if pressed then
                        if pressed == 27 then
                            is_binding_key = false
                            keybind_status = 'Назначение клавиши отменено.'
                        elseif isBindableKey(pressed) then
                            settings.main.open_key = pressed
                            inicfg.save(settings, ini_name)
                            is_binding_key = false
                            keybind_status = 'Новая клавиша сохранена: ' .. keycodeToName(pressed)
                        end
                    end
                end
            else
                if wasKeyPressed(settings.main.open_key) then toggleMenu() end
            end
        end
    end
end

imgui.OnFrame(
    function() return window_state[0] end,
    function()
        if not style_applied then applyStyle(); style_applied = true end
        imgui.SetNextWindowSize(imgui.ImVec2(1280,760), imgui.Cond.FirstUseEver)
        imgui.Begin('Rules by Runelli', window_state, imgui.WindowFlags.NoCollapse)
        local winPos, winSize = imgui.GetWindowPos(), imgui.GetWindowSize()
        drawGradientRect(imgui.GetWindowDrawList(), winPos, imgui.ImVec2(winPos.x+winSize.x, winPos.y+winSize.y), COLORS.bg1, COLORS.bg2, COLORS.bg3, COLORS.bg1)
        renderCenteredTextLine('Rules by Runelli', COLORS.title, 1.18)
        imgui.SetCursorPosY(imgui.GetCursorPosY() - 2)
        renderCenteredTextLine('Свод правил Arizona RP', COLORS.gray, 1.0)
        imgui.Spacing()
        local p = imgui.GetCursorScreenPos()
        imgui.GetWindowDrawList():AddLine(imgui.ImVec2(p.x+20, p.y+2), imgui.ImVec2(p.x+imgui.GetContentRegionAvail().x-20, p.y+2), toU32(COLORS.border), 1.0)
        imgui.Dummy(imgui.ImVec2(0,8))
        local leftW = 390
        local avail = imgui.GetContentRegionAvail()
        beginGradientChild('##left_panel', imgui.ImVec2(leftW, avail.y), true); renderLeftMenu(); imgui.EndChild()
        imgui.SameLine()
        beginGradientChild('##right_panel', imgui.ImVec2(0, avail.y), true)

        -- Вкладки: просмотр и поиск
        if imgui.BeginTabBar('##main_tabs') then
            if imgui.BeginTabItem('Просмотр правил') then
                active_tab = 0
                local curCat = RULES[selected_category]
                local curRule = getCurrentRule()
                renderRuleHeaderCard(curCat, curRule)
                renderViewTab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem('Поиск') then
                active_tab = 1
                renderSearchResultsTab()
                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end

        imgui.EndChild()
        imgui.End()
    end
)