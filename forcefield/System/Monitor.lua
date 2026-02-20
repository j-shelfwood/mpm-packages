local this

local function ensureMonitor()
    if this.monitor then
        return this.monitor
    end

    this.monitor = peripheral.find("monitor")
    if this.monitor then
        this.monitor.setTextScale(1)
    end
    return this.monitor
end

this = {
    monitor = nil,
    init = function()
        if not ensureMonitor() then
            print("No monitor found, cannot initialize monitor interface...")
            return
        end
        this.clear()
    end,
    clear = function()
        if not ensureMonitor() then
            return
        end
        this.monitor.clear()
        this.monitor.setCursorPos(1, 1)
    end,
    render = function(status)
        if not ensureMonitor() then
            return
        end

        -- If a stale peripheral reference exists after detach/re-attach, reacquire.
        local ok = pcall(function()
            this.clear()
            this.monitor.write("Forcefield Status: " .. (status.enabled and "Enabled" or "Disabled"))
            this.monitor.setCursorPos(1, 2)
            this.monitor.write("Block: " .. status.block)
            this.monitor.setCursorPos(1, 3)
            this.monitor.write("Invisible: " .. tostring(status.invisible))
            this.monitor.setCursorPos(1, 4)
            this.monitor.write("Player Passable: " .. tostring(status.playerPassable))
        end)

        if not ok then
            this.monitor = nil
            if ensureMonitor() then
                this.clear()
            end
        end
    end
}

return this
