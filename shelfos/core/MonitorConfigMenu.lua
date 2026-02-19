-- MonitorConfigMenu.lua
-- View selection and configuration UI for monitors
-- Uses ui/List for view picker and ConfigUI for view settings
-- Extracted from Monitor.lua for maintainability

local ViewManager = mpm('views/Manager')
local ConfigUI = mpm('shelfos/core/ConfigUI')
local ScrollableList = mpm('ui/ScrollableList')

local MonitorConfigMenu = {}

-- Draw the view selection menu using ui/List
-- Uses raw peripheral for interactive menus (not buffered)
-- @param peripheral Raw monitor peripheral
-- @param availableViews Array of view names
-- @param currentViewName Currently selected view name
-- @return selected view name or nil if cancelled
function MonitorConfigMenu.showViewSelector(peripheral, availableViews, currentViewName)
    local selected = ScrollableList.new(peripheral, availableViews, {
        title = "Select View",
        selected = currentViewName,
        cancelText = "Cancel",
        showPageIndicator = false,
        formatFn = function(viewName)
            return viewName
        end
    }):show()

    return selected
end

-- Show view configuration if the view has a configSchema
-- @param peripheral Raw monitor peripheral
-- @param viewName View to configure
-- @param currentConfig Current view configuration
-- @return newConfig table, or nil if cancelled or no config needed
function MonitorConfigMenu.showViewConfig(peripheral, viewName, currentConfig)
    local View = ViewManager.load(viewName)

    if not View or not View.configSchema or #View.configSchema == 0 then
        return nil, false  -- No config needed
    end

    local newConfig = ConfigUI.drawConfigMenu(
        peripheral,
        viewName,
        View.configSchema,
        currentConfig or {}
    )

    return newConfig, true  -- true = had config schema
end

-- Complete config flow: view selection + optional configuration
-- @param monitor Monitor instance (needs peripheral, availableViews, viewName, viewConfig)
-- @param onViewChange Callback(peripheralName, viewName, viewConfig)
-- @return selectedView, newConfig, or nil if cancelled
function MonitorConfigMenu.openConfigFlow(monitor)
    local peripheral = monitor.peripheral

    -- Favor the monitor's cached list for instant menu open.
    -- Recomputing mountability can be expensive on touch path.
    local availableViews = monitor.availableViews
    if not availableViews or #availableViews == 0 then
        availableViews = ViewManager.getSelectableViews()
    end
    monitor.availableViews = availableViews

    local currentViewName = monitor.viewName
    local currentConfig = monitor.viewConfig

    -- Step 1: Select view
    local selectedView = MonitorConfigMenu.showViewSelector(
        peripheral,
        availableViews,
        currentViewName
    )

    if not selectedView or selectedView == "cancel" then
        return nil, nil
    end

    -- Step 2: Configure view (if it has configSchema)
    local newConfig, hadSchema = MonitorConfigMenu.showViewConfig(
        peripheral,
        selectedView,
        currentConfig
    )

    if hadSchema then
        if newConfig then
            -- User completed config
            return selectedView, newConfig
        else
            -- User cancelled config - don't change view
            return nil, nil
        end
    else
        -- No config schema - return empty config
        return selectedView, {}
    end
end

return MonitorConfigMenu
