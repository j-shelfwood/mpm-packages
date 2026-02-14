-- ViewZones.lua
-- Zone registry display for shelfos-swarm pocket computer
-- Scrollable colored zone list with keyboard navigation
-- Shows zone status, ID, and fingerprint

local TermUI = mpm('shelfos-swarm/ui/TermUI')
local Core = mpm('ui/Core')

local ViewZones = {}

-- Internal state
local state = {
    zones = {},
    scrollOffset = 0,
    pageSize = 0  -- calculated from screen height
}

function ViewZones.onEnter(ctx, args)
    state.zones = ctx.app.authority:getZones()
    state.scrollOffset = 0
    -- Each zone takes 2 rows + 1 spacing, header=2, footer=2
    state.pageSize = math.floor((ctx.height - 4) / 3)
end

function ViewZones.draw(ctx)
    TermUI.clear()
    TermUI.drawTitleBar("Zone Registry")

    local zones = state.zones
    local y = 3

    if #zones == 0 then
        TermUI.drawText(2, y, "No zones registered.", colors.lightGray)
        y = y + 2
        TermUI.drawText(2, y, "Use [A] Add Zone from the", colors.gray)
        y = y + 1
        TermUI.drawText(2, y, "main menu to pair computers.", colors.gray)
    else
        -- Zone count header
        TermUI.drawText(2, y, #zones .. " zone(s) registered", colors.lightGray)
        y = y + 1

        -- Scrollable zone list
        local startIdx = state.scrollOffset + 1
        local endIdx = math.min(#zones, state.scrollOffset + state.pageSize)

        -- Scroll up indicator
        if state.scrollOffset > 0 then
            TermUI.drawText(ctx.width, y, "^", colors.yellow)
        end
        y = y + 1

        for i = startIdx, endIdx do
            local zone = zones[i]
            if zone and y < ctx.height - 2 then
                -- Status icon + name
                local statusIcon, statusColor
                if zone.status == "active" then
                    statusIcon = "+"
                    statusColor = colors.lime
                else
                    statusIcon = "x"
                    statusColor = colors.red
                end

                term.setCursorPos(2, y)
                term.setTextColor(statusColor)
                term.write(statusIcon)
                term.setTextColor(colors.white)
                term.write(" " .. Core.truncate(zone.label, ctx.width - 4))
                y = y + 1

                -- Details line
                local fp = zone.fingerprint or "?"
                if #fp > 8 then fp = fp:sub(1, 8) .. ".." end
                local details = "ID: " .. zone.id .. "  FP: " .. fp
                term.setCursorPos(4, y)
                term.setTextColor(colors.lightGray)
                term.write(Core.truncate(details, ctx.width - 5))
                y = y + 1

                -- Spacing between zones
                y = y + 1
            end
        end

        -- Scroll down indicator
        if endIdx < #zones then
            TermUI.drawText(ctx.width, y - 1, "v", colors.yellow)
        end

        -- Page indicator
        local totalPages = math.max(1, math.ceil(#zones / state.pageSize))
        local currentPage = math.floor(state.scrollOffset / state.pageSize) + 1
        local pageText = "Page " .. currentPage .. "/" .. totalPages
        TermUI.drawCentered(ctx.height - 1, pageText, colors.lightGray)
    end

    term.setTextColor(colors.white)
    TermUI.drawStatusBar({{ key = "B", label = "Back" }})
end

function ViewZones.handleEvent(ctx, event, p1, ...)
    if event == "key" then
        local keyName = keys.getName(p1)
        if not keyName then return nil end
        keyName = keyName:lower()

        if keyName == "b" or keyName == "backspace" then
            return "pop"
        end

        -- Scroll navigation
        if keyName == "up" and state.scrollOffset > 0 then
            state.scrollOffset = state.scrollOffset - 1
            ViewZones.draw(ctx)
        elseif keyName == "down" then
            local maxOffset = math.max(0, #state.zones - state.pageSize)
            if state.scrollOffset < maxOffset then
                state.scrollOffset = state.scrollOffset + 1
                ViewZones.draw(ctx)
            end
        elseif keyName == "pageup" then
            state.scrollOffset = math.max(0, state.scrollOffset - state.pageSize)
            ViewZones.draw(ctx)
        elseif keyName == "pagedown" then
            local maxOffset = math.max(0, #state.zones - state.pageSize)
            state.scrollOffset = math.min(maxOffset, state.scrollOffset + state.pageSize)
            ViewZones.draw(ctx)
        end
    end

    return nil
end

return ViewZones
