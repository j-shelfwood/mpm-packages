-- SwarmStatus.lua
-- Main swarm overview screen for pocket computer
-- Shows visual representation of all swarm nodes with status

local Protocol = mpm('net/Protocol')
local EventUtils = mpm('utils/EventUtils')

local SwarmStatus = {}

-- Node status indicators
local STATUS = {
    ONLINE = { char = "O", color = colors.lime },
    OFFLINE = { char = "X", color = colors.red },
    UNKNOWN = { char = "?", color = colors.gray },
    SELF = { char = "@", color = colors.yellow }
}

-- Get terminal dimensions
local function getSize()
    return term.getSize()
end

-- Draw a single node box
-- @param x X position
-- @param y Y position
-- @param node Node data {id, name, status, peripherals}
-- @param selected Whether this node is selected
local function drawNode(x, y, node, selected)
    local w, h = getSize()
    local boxWidth = math.min(12, math.floor((w - 2) / 2))
    local boxHeight = 3

    -- Box border color
    if selected then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.blue)
    else
        term.setTextColor(colors.lightGray)
        term.setBackgroundColor(colors.black)
    end

    -- Draw box top
    term.setCursorPos(x, y)
    term.write("+" .. string.rep("-", boxWidth - 2) .. "+")

    -- Draw box middle with status
    term.setCursorPos(x, y + 1)
    term.write("|")

    -- Status indicator
    local status = STATUS[node.status] or STATUS.UNKNOWN
    term.setTextColor(status.color)
    term.write(status.char)

    -- Node name (truncated)
    term.setTextColor(selected and colors.white or colors.lightGray)
    local nameSpace = boxWidth - 4
    local displayName = node.name:sub(1, nameSpace)
    term.write(displayName .. string.rep(" ", nameSpace - #displayName))
    term.write("|")

    -- Draw box bottom
    term.setCursorPos(x, y + 2)
    term.setTextColor(selected and colors.white or colors.lightGray)
    term.write("+" .. string.rep("-", boxWidth - 2) .. "+")

    -- Reset colors
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Draw the header
local function drawHeader(nodeCount, onlineCount)
    local w, _ = getSize()

    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()

    local title = " SWARM STATUS "
    local stats = onlineCount .. "/" .. nodeCount .. " "
    term.setCursorPos(1, 1)
    term.write(title)
    term.setCursorPos(w - #stats + 1, 1)
    term.setTextColor(colors.lime)
    term.write(stats)

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Draw the bottom menu bar
local function drawMenuBar()
    local w, h = getSize()

    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()

    -- Menu options
    local menu = {
        { key = "A", label = "Add" },
        { key = "R", label = "Refresh" },
        { key = "N", label = "Notif" },
        { key = "Q", label = "Quit" }
    }

    local x = 1
    for _, item in ipairs(menu) do
        term.setCursorPos(x, h)
        term.setTextColor(colors.yellow)
        term.write("[" .. item.key .. "]")
        term.setTextColor(colors.white)
        term.write(item.label .. " ")
        x = x + #item.key + #item.label + 4
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Draw "no nodes" message
local function drawEmpty()
    local w, h = getSize()
    local msg1 = "No computers in swarm"
    local msg2 = "Press [A] to add one"

    term.setTextColor(colors.gray)
    term.setCursorPos(math.floor((w - #msg1) / 2) + 1, math.floor(h / 2) - 1)
    term.write(msg1)
    term.setCursorPos(math.floor((w - #msg2) / 2) + 1, math.floor(h / 2) + 1)
    term.write(msg2)
    term.setTextColor(colors.white)
end

-- Draw all nodes in a grid
local function drawNodes(nodes, selectedIndex)
    local w, h = getSize()
    local boxWidth = math.min(12, math.floor((w - 2) / 2))
    local boxHeight = 4
    local cols = math.floor(w / (boxWidth + 1))
    local startY = 3  -- After header

    -- Clear content area
    for y = 2, h - 1 do
        term.setCursorPos(1, y)
        term.clearLine()
    end

    if #nodes == 0 then
        drawEmpty()
        return
    end

    -- Draw nodes in grid
    for i, node in ipairs(nodes) do
        local col = ((i - 1) % cols)
        local row = math.floor((i - 1) / cols)
        local x = col * (boxWidth + 1) + 1
        local y = startY + row * boxHeight

        -- Check if node fits on screen
        if y + boxHeight <= h - 1 then
            drawNode(x, y, node, i == selectedIndex)
        end
    end
end

-- Draw detailed info for selected node
local function drawNodeDetail(node)
    local w, h = getSize()
    local detailY = h - 3

    if not node then return end

    term.setCursorPos(1, detailY)
    term.setTextColor(colors.lightGray)
    term.clearLine()

    -- Show node details
    local info = node.name
    if node.computerId then
        info = info .. " #" .. node.computerId
    end
    if node.peripheralCount and node.peripheralCount > 0 then
        info = info .. " [" .. node.peripheralCount .. " periph]"
    end

    term.write(info:sub(1, w))
    term.setTextColor(colors.white)
end

-- Build node list from discovery and config
-- @param discovery Discovery instance
-- @param pairedComputers Table of paired computer IDs (from config)
-- @return Array of node data
local function buildNodeList(discovery, pairedComputers)
    local nodes = {}
    local seenIds = {}

    -- Add self (pocket) as first node
    table.insert(nodes, {
        id = "self",
        computerId = os.getComputerID(),
        name = "Pocket",
        status = "SELF",
        peripheralCount = 0
    })
    seenIds[os.getComputerID()] = true

    -- Add discovered zones
    if discovery then
        local zones = discovery:getZones()
        for _, zone in ipairs(zones) do
            if not seenIds[zone.computerId] then
                table.insert(nodes, {
                    id = zone.zoneId,
                    computerId = zone.computerId,
                    name = zone.zoneName or ("Zone #" .. zone.computerId),
                    status = "ONLINE",
                    peripheralCount = zone.monitors and #zone.monitors or 0
                })
                seenIds[zone.computerId] = true
            end
        end
    end

    -- Add paired computers that aren't online
    if pairedComputers then
        for _, comp in ipairs(pairedComputers) do
            if not seenIds[comp.computerId] then
                table.insert(nodes, {
                    id = comp.id or ("paired_" .. comp.computerId),
                    computerId = comp.computerId,
                    name = comp.name or ("Computer #" .. comp.computerId),
                    status = "OFFLINE",
                    peripheralCount = 0
                })
                seenIds[comp.computerId] = true
            end
        end
    end

    return nodes
end

-- Count online nodes
local function countOnline(nodes)
    local count = 0
    for _, node in ipairs(nodes) do
        if node.status == "ONLINE" or node.status == "SELF" then
            count = count + 1
        end
    end
    return count
end

-- Main render function
-- @param nodes Array of node data
-- @param selectedIndex Currently selected node index
function SwarmStatus.render(nodes, selectedIndex)
    term.clear()

    local onlineCount = countOnline(nodes)
    drawHeader(#nodes, onlineCount)
    drawNodes(nodes, selectedIndex)

    if selectedIndex > 0 and selectedIndex <= #nodes then
        drawNodeDetail(nodes[selectedIndex])
    end

    drawMenuBar()
end

-- Run the swarm status screen
-- @param discovery Discovery instance
-- @param callbacks Table of callbacks: onAdd(), onNotifications(), onQuit(), onRefresh()
-- @param pairedComputers Optional table of paired computers from config
-- @return action string ("add", "notifications", "quit", "refresh")
function SwarmStatus.run(discovery, callbacks, pairedComputers)
    local selectedIndex = 1
    local lastRefresh = os.epoch("utc")
    local refreshInterval = 5000  -- 5 seconds

    -- Initial discovery before first render
    if discovery then
        -- Show loading state
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        print("Discovering swarm...")
        term.setTextColor(colors.white)

        -- Do blocking discovery (2 second timeout)
        discovery:discover(2)
    end

    local nodes = buildNodeList(discovery, pairedComputers)

    -- Initial render
    SwarmStatus.render(nodes, selectedIndex)

    while true do
        -- Auto-refresh periodically
        local now = os.epoch("utc")
        if now - lastRefresh > refreshInterval then
            if discovery then
                -- Trigger discovery in background
                discovery:discover(1)
            end
            nodes = buildNodeList(discovery, pairedComputers)
            SwarmStatus.render(nodes, selectedIndex)
            lastRefresh = now
        end

        -- Wait for input with short timeout for refresh
        local timer = os.startTimer(1)
        local event, p1 = os.pullEvent()

        if event == "key" then
            local key = p1

            if key == keys.q then
                return "quit"

            elseif key == keys.a then
                return "add"

            elseif key == keys.n then
                return "notifications"

            elseif key == keys.r then
                -- Manual refresh
                term.setCursorPos(1, 2)
                term.setTextColor(colors.yellow)
                term.write("Refreshing...")
                term.setTextColor(colors.white)

                if discovery then
                    discovery:discover(2)
                end
                nodes = buildNodeList(discovery, pairedComputers)
                lastRefresh = os.epoch("utc")
                SwarmStatus.render(nodes, selectedIndex)

            elseif key == keys.up then
                if selectedIndex > 1 then
                    selectedIndex = selectedIndex - 1
                    SwarmStatus.render(nodes, selectedIndex)
                end

            elseif key == keys.down then
                if selectedIndex < #nodes then
                    selectedIndex = selectedIndex + 1
                    SwarmStatus.render(nodes, selectedIndex)
                end

            elseif key == keys.left then
                local w, _ = getSize()
                local boxWidth = math.min(12, math.floor((w - 2) / 2))
                local cols = math.floor(w / (boxWidth + 1))
                if selectedIndex > cols then
                    selectedIndex = selectedIndex - cols
                    SwarmStatus.render(nodes, selectedIndex)
                end

            elseif key == keys.right then
                local w, _ = getSize()
                local boxWidth = math.min(12, math.floor((w - 2) / 2))
                local cols = math.floor(w / (boxWidth + 1))
                if selectedIndex + cols <= #nodes then
                    selectedIndex = selectedIndex + cols
                    SwarmStatus.render(nodes, selectedIndex)
                end

            elseif key == keys.enter and selectedIndex > 0 and selectedIndex <= #nodes then
                -- Could expand to show node details
                -- For now, just flash selection
                SwarmStatus.render(nodes, selectedIndex)
            end

        elseif event == "timer" and p1 == timer then
            -- Refresh timer - rerender to update status
            nodes = buildNodeList(discovery, pairedComputers)
            SwarmStatus.render(nodes, selectedIndex)
        end
    end
end

return SwarmStatus
