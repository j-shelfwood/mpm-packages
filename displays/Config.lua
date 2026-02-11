local this

this = {
    load = function()
        if fs.exists("displays.config") then
            local file = fs.open("displays.config", "r")
            local config = textutils.unserialize(file.readAll())
            file.close()
            return config
        else
            return {}
        end
    end,

    save = function(config)
        local file = fs.open("displays.config", "w")
        file.write(textutils.serialize(config))
        file.close()
    end,

    -- Update a single display's view and persist
    updateDisplayView = function(monitorName, viewName)
        local config = this.load()
        for _, display in ipairs(config) do
            if display.monitor == monitorName then
                display.view = viewName
                break
            end
        end
        this.save(config)
    end
}

return this
