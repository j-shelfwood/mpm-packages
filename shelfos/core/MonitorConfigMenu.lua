-- MonitorConfigMenu.lua
-- View selection and configuration UI for monitors.
-- Shows all views (installed and uninstalled) grouped by category.
-- Uninstalled views show a [↓] indicator and trigger package install on selection.

local ViewManager      = mpm('views/Manager')
local ConfigUI         = mpm('shelfos/core/ConfigUI')
local ScrollableList   = mpm('ui/ScrollableList')
local PackageInstaller = mpm('views/PackageInstaller')
local Core             = mpm('ui/Core')

local MonitorConfigMenu = {}

-- Build a flat items array with group header sentinels interspersed.
-- Returns { items, nameByIndex } where nameByIndex[rawIndex] = viewName
local function buildGroupedItems()
    local groups = ViewManager.getAvailableViewsGrouped()
    local items = {}

    for _, group in ipairs(groups) do
        -- Group header sentinel
        table.insert(items, { _group = group.label })

        for _, view in ipairs(group.views) do
            -- Store all needed info directly on the item table
            table.insert(items, {
                name      = view.name,
                label     = view.label,
                installed = view.installed,
                package   = view.package,
            })
        end
    end

    return items
end

-- Draw a simple status screen on the raw monitor peripheral.
-- Used for install progress (pre-buffer, blocking).
local function drawStatus(peripheral, title, lines)
    peripheral.setBackgroundColor(colors.black)
    peripheral.setTextColor(colors.white)
    peripheral.clear()
    peripheral.setCursorPos(1, 1)

    local w = select(1, peripheral.getSize())

    -- Title bar
    peripheral.setBackgroundColor(colors.blue)
    peripheral.setTextColor(colors.white)
    peripheral.setCursorPos(1, 1)
    peripheral.write(string.rep(" ", w))
    peripheral.setCursorPos(2, 1)
    peripheral.write(title:sub(1, w - 2))
    peripheral.setBackgroundColor(colors.black)

    -- Status lines
    for i, line in ipairs(lines) do
        peripheral.setCursorPos(2, i + 2)
        peripheral.setTextColor(colors.lightGray)
        peripheral.write(tostring(line):sub(1, w - 2))
    end
end

-- Show install confirmation dialog. Returns true if user confirms.
-- @param mon Raw monitor peripheral (wrapped)
-- @param monName Peripheral name string (for event matching)
-- @param pkgName Package name to install
local function showInstallConfirm(mon, monName, pkgName)
    local w, h = mon.getSize()

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()

    -- Title
    mon.setBackgroundColor(colors.blue)
    mon.setCursorPos(1, 1)
    mon.write(string.rep(" ", w))
    mon.setCursorPos(2, 1)
    mon.write("Install Package?")
    mon.setBackgroundColor(colors.black)

    -- Package name
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(2, 3)
    mon.write(pkgName)

    -- Description
    mon.setTextColor(colors.lightGray)
    mon.setCursorPos(2, 4)
    mon.write("This view requires a package")
    mon.setCursorPos(2, 5)
    mon.write("that is not yet installed.")
    mon.setCursorPos(2, 6)
    mon.write("Download and install it now?")

    -- Buttons
    local btnY = h - 1
    local installLabel = " Install "
    local cancelLabel  = " Cancel "
    local totalW = #installLabel + #cancelLabel + 2
    local startX = math.floor((w - totalW) / 2) + 1

    local installX1 = startX
    local installX2 = startX + #installLabel - 1
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.white)
    mon.setCursorPos(installX1, btnY)
    mon.write(installLabel)

    local cancelX1 = installX2 + 2
    local cancelX2 = cancelX1 + #cancelLabel - 1
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    mon.setCursorPos(cancelX1, btnY)
    mon.write(cancelLabel)

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)

    while true do
        local evt, pName, tx, ty = os.pullEvent("monitor_touch")
        if pName == monName then
            if ty == btnY then
                if tx >= installX1 and tx <= installX2 then
                    return true
                elseif tx >= cancelX1 and tx <= cancelX2 then
                    return false
                end
            end
        end
    end
end

-- Attempt to install a package, showing progress on the monitor.
-- @param mon Raw monitor peripheral (wrapped)
-- @param monName Peripheral name string
-- @param pkgName Package name to install
-- Returns true on success, false on failure.
local function doInstall(mon, monName, pkgName)
    drawStatus(mon, "Downloading", { "Installing " .. pkgName .. "..." })

    local logLines = { "Starting..." }

    local success, err = PackageInstaller.install(pkgName, function(msg)
        table.insert(logLines, msg)
        local showLines = {}
        local startIdx = math.max(1, #logLines - 5)
        for i = startIdx, #logLines do
            table.insert(showLines, logLines[i])
        end
        drawStatus(mon, "Downloading " .. pkgName, showLines)
    end)

    if success then
        drawStatus(mon, "Installed!", {
            pkgName .. " installed successfully.",
            "",
            "Loading view..."
        })
        os.sleep(1)
        ViewManager.clearCache()
        return true
    else
        drawStatus(mon, "Install Failed", {
            "Error installing " .. pkgName .. ":",
            tostring(err) or "Unknown error",
            "",
            "Touch to continue"
        })
        while true do
            local evt, pName = os.pullEvent("monitor_touch")
            if pName == monName then break end
        end
        return false
    end
end

-- Draw the view selection menu using ScrollableList with grouped items.
-- @param peripheral Raw monitor peripheral
-- @param currentViewName Currently selected view name
-- @return selected item table or nil if cancelled
function MonitorConfigMenu.showViewSelector(peripheral, currentViewName)
    local items = buildGroupedItems()

    local selected = ScrollableList.new(peripheral, items, {
        title      = "Select View",
        selected   = currentViewName,
        cancelText = "Cancel",
        showPageIndicator = false,
        valueFn = function(item)
            if type(item) == "table" and item.name then return item.name end
            return item
        end,
        formatFn = function(item)
            if type(item) == "table" and item.name then
                local label = item.label or item.name
                if not item.installed then
                    label = label .. " [\x19]"  -- down-arrow indicator
                    return { text = label, color = colors.gray }
                end
                return { text = label, color = colors.white }
            end
            return tostring(item)
        end,
    }):show()

    -- show() returns the raw item table or nil
    if type(selected) == "table" and selected.name then
        return selected
    end
    return nil
end

-- Show view configuration if the view has a configSchema.
function MonitorConfigMenu.showViewConfig(peripheral, viewName, currentConfig)
    local View = ViewManager.load(viewName)

    if not View or not View.configSchema or #View.configSchema == 0 then
        return nil, false
    end

    local newConfig = ConfigUI.drawConfigMenu(
        peripheral,
        viewName,
        View.configSchema,
        currentConfig or {}
    )

    return newConfig, true
end

-- Complete config flow: view selection + optional install + optional configuration.
-- @param monitor Monitor instance (needs .peripheral, .viewName, .viewConfig, .availableViews)
-- @return selectedViewName, newConfig  OR  nil, nil if cancelled
function MonitorConfigMenu.openConfigFlow(monitor)
    local mon     = monitor.peripheral
    local monName = monitor.peripheralName

    -- Step 1: Select view (grouped, shows installed + uninstalled)
    local selectedItem = MonitorConfigMenu.showViewSelector(mon, monitor.viewName)

    if not selectedItem then
        return nil, nil
    end

    local selectedViewName = selectedItem.name

    -- Step 2: If view package not installed, prompt to install
    if not selectedItem.installed then
        local pkgName = selectedItem.package

        local confirmed = showInstallConfirm(mon, monName, pkgName)
        if not confirmed then
            return nil, nil
        end

        local installed = doInstall(mon, monName, pkgName)
        if not installed then
            return nil, nil
        end
    end

    -- Step 3: Configure view (if it has configSchema)
    local newConfig, hadSchema = MonitorConfigMenu.showViewConfig(
        mon,
        selectedViewName,
        monitor.viewConfig
    )

    if hadSchema then
        if newConfig then
            return selectedViewName, newConfig
        else
            return nil, nil
        end
    else
        return selectedViewName, {}
    end
end

return MonitorConfigMenu
