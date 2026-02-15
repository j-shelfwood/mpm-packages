-- ViewComputers.lua
-- Computer registry display for shelfos-swarm pocket computer
-- Scrollable colored computer list with keyboard navigation
-- Shows computer status, ID, and fingerprint

local TermUI = mpm('ui/TermUI')
local Core = mpm('ui/Core')

local ViewComputers = {}

-- Internal state
local state = {
    computers = {},
    scrollOffset = 0,
    pageSize = 0  -- calculated from screen height
}

function ViewComputers.onEnter(ctx, args)
    state.computers = ctx.app.authority:getComputers()
    state.scrollOffset = 0
    -- Each computer takes 2 rows + 1 spacing, header=2, footer=2
    state.pageSize = math.floor((ctx.height - 4) / 3)
end

function ViewComputers.draw(ctx)
    TermUI.clear()
    TermUI.drawTitleBar("Computer Registry")

    local computers = state.computers
    local y = 3

    if #computers == 0 then
        TermUI.drawText(2, y, "No computers registered.", colors.lightGray)
        y = y + 2
        TermUI.drawText(2, y, "Use [A] Add Computer from", colors.gray)
        y = y + 1
        TermUI.drawText(2, y, "the main menu to pair.", colors.gray)
    else
        -- Computer count header
        TermUI.drawText(2, y, #computers .. " computer(s) registered", colors.lightGray)
        y = y + 1

        -- Scrollable computer list
        local startIdx = state.scrollOffset + 1
        local endIdx = math.min(#computers, state.scrollOffset + state.pageSize)

        -- Scroll up indicator
        if state.scrollOffset > 0 then
            TermUI.drawText(ctx.width, y, "^", colors.yellow)
        end
        y = y + 1

        for i = startIdx, endIdx do
            local computer = computers[i]
            if computer and y < ctx.height - 2 then
                -- Status icon + name
                local statusIcon, statusColor
                if computer.status == "active" then
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
                term.write(" " .. Core.truncate(computer.label, ctx.width - 4))
                y = y + 1

                -- Details line
                local fp = computer.fingerprint or "?"
                if #fp > 8 then fp = fp:sub(1, 8) .. ".." end
                local details = "ID: " .. computer.id .. "  FP: " .. fp
                term.setCursorPos(4, y)
                term.setTextColor(colors.lightGray)
                term.write(Core.truncate(details, ctx.width - 5))
                y = y + 1

                -- Spacing between computers
                y = y + 1
            end
        end

        -- Scroll down indicator
        if endIdx < #computers then
            TermUI.drawText(ctx.width, y - 1, "v", colors.yellow)
        end

        -- Page indicator
        local totalPages = math.max(1, math.ceil(#computers / state.pageSize))
        local currentPage = math.floor(state.scrollOffset / state.pageSize) + 1
        local pageText = "Page " .. currentPage .. "/" .. totalPages
        TermUI.drawCentered(ctx.height - 1, pageText, colors.lightGray)
    end

    term.setTextColor(colors.white)
    TermUI.drawStatusBar({{ key = "B", label = "Back" }})
end

function ViewComputers.handleEvent(ctx, event, p1, ...)
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
            ViewComputers.draw(ctx)
        elseif keyName == "down" then
            local maxOffset = math.max(0, #state.computers - state.pageSize)
            if state.scrollOffset < maxOffset then
                state.scrollOffset = state.scrollOffset + 1
                ViewComputers.draw(ctx)
            end
        elseif keyName == "pageup" then
            state.scrollOffset = math.max(0, state.scrollOffset - state.pageSize)
            ViewComputers.draw(ctx)
        elseif keyName == "pagedown" then
            local maxOffset = math.max(0, #state.computers - state.pageSize)
            state.scrollOffset = math.min(maxOffset, state.scrollOffset + state.pageSize)
            ViewComputers.draw(ctx)
        end
    end

    return nil
end

return ViewComputers
