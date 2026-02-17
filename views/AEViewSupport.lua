-- AEViewSupport.lua
-- Shared lifecycle helpers for AE-backed views/factories

local AEInterface = mpm("peripherals/" .. "AEInterface")

local AEViewSupport = {}

function AEViewSupport.mount(mountCheck)
    if mountCheck then
        return mountCheck()
    end
    if not AEInterface or type(AEInterface.exists) ~= "function" then
        return false
    end
    local ok, exists = pcall(AEInterface.exists)
    return ok and exists == true
end

function AEViewSupport.init(self)
    if not AEInterface or type(AEInterface.new) ~= "function" then
        self.interface = nil
        return nil
    end
    local ok, interface = pcall(AEInterface.new)
    self.interface = ok and interface or nil
    return self.interface
end

function AEViewSupport.ensureInterface(self)
    if self.interface then
        return true, self.interface
    end

    local interface = AEViewSupport.init(self)
    if interface then
        return true, interface
    end

    return false, nil
end

return AEViewSupport
