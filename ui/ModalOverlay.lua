-- ModalOverlay.lua
-- Shared blocking modal helper for monitor touch interactions

local Core = mpm('ui/Core')
local EventUtils = mpm('utils/EventUtils')

local ModalOverlay = {}

local function inBounds(x, y, x1, y1, x2, y2)
    return x >= x1 and x <= x2 and y >= y1 and y <= y2
end

local function calculateBounds(monitor, opts)
    local width, height = monitor.getSize()
    local margin = opts.margin or 1
    local overlayWidth = opts.width or math.min(width - (margin * 2), opts.maxWidth or (width - 2))
    local overlayHeight = opts.height or math.min(height - (margin * 2), opts.maxHeight or (height - 2))

    overlayWidth = math.max(4, math.min(overlayWidth, width - (margin * 2)))
    overlayHeight = math.max(4, math.min(overlayHeight, height - (margin * 2)))

    local x1 = math.floor((width - overlayWidth) / 2) + 1
    local y1 = math.floor((height - overlayHeight) / 2) + 1
    local x2 = x1 + overlayWidth - 1
    local y2 = y1 + overlayHeight - 1

    return {
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        width = overlayWidth,
        height = overlayHeight
    }
end

local function drawBase(monitor, frame, opts)
    local bg = opts.backgroundColor or colors.gray
    monitor.setBackgroundColor(bg)
    for y = frame.y1, frame.y2 do
        monitor.setCursorPos(frame.x1, y)
        monitor.write(string.rep(" ", frame.width))
    end

    if opts.title then
        monitor.setBackgroundColor(opts.titleBackgroundColor or colors.lightGray)
        monitor.setTextColor(opts.titleTextColor or colors.black)
        monitor.setCursorPos(frame.x1, frame.y1)
        monitor.write(string.rep(" ", frame.width))
        monitor.setCursorPos(frame.x1 + 1, frame.y1)
        monitor.write(Core.truncate(opts.title, frame.width - 2))
    end
end

function ModalOverlay.show(target, opts)
    opts = opts or {}

    local monitor = target.monitor or target
    local monitorName = target.peripheralName or opts.peripheralName
    local state = opts.state or {}

    while true do
        local frame = calculateBounds(monitor, opts)
        drawBase(monitor, frame, opts)

        local actions = {}
        local function addAction(id, x1, y1, x2, y2)
            table.insert(actions, { id = id, x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
        end

        if opts.render then
            opts.render(monitor, frame, state, addAction)
        end

        Core.resetColors(monitor)

        local _, tx, ty = EventUtils.waitForTouch(monitorName)

        if not inBounds(tx, ty, frame.x1, frame.y1, frame.x2, frame.y2) then
            if opts.closeOnOutside ~= false then
                return state
            end
        else
            local hit = nil
            for _, action in ipairs(actions) do
                if inBounds(tx, ty, action.x1, action.y1, action.x2, action.y2) then
                    hit = action.id
                    break
                end
            end

            if opts.onTouch then
                local done, result = opts.onTouch(monitor, frame, state, tx, ty, hit)
                if done then
                    return result
                end
            end
        end
    end
end

return ModalOverlay
