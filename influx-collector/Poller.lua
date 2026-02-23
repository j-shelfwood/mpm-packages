local MachineActivity = mpm('peripherals/MachineActivity')
local EnergyInterface = mpm('peripherals/EnergyInterface')

local Poller = {}
Poller.__index = Poller

local function nowMs()
    return os.epoch("utc")
end

local function sumCounts(list, field)
    local total = 0
    for _, item in ipairs(list) do
        local value = item[field]
        if type(value) == "number" then
            total = total + value
        end
    end
    return total
end

local function sortByField(list, field)
    table.sort(list, function(a, b)
        return (a[field] or 0) > (b[field] or 0)
    end)
end

function Poller.new(config, influx, discovery)
    local self = setmetatable({}, Poller)
    self.config = config
    self.influx = influx
    self.discovery = discovery
    self.nextMachineAt = 0
    self.nextEnergyAt = 0
    self.nextAeAt = 0
    return self
end

function Poller:collectMachines()
    local timestamp = nowMs()
    local machineTypes = self.discovery:getMachines()

    for _, entry in ipairs(machineTypes) do
        for idx, machine in ipairs(entry.machines) do
            local active, data = MachineActivity.getActivity(machine.peripheral)
            local fields = {
                active = active and 1 or 0
            }

            if type(data.progress) == "number" then
                fields.progress = data.progress
            end
            if type(data.total) == "number" then
                fields.progress_total = data.total
            end
            if type(data.percent) == "number" then
                fields.progress_percent = data.percent
            end
            if type(data.rate) == "number" then
                fields.production_rate = data.rate
            end
            if type(data.usage) == "number" then
                fields.energy_usage = data.usage
            end

            local energyPercent = MachineActivity.getEnergyPercent(machine.peripheral)
            if type(energyPercent) == "number" then
                fields.energy_percent = energyPercent * 100
            end

            local formed = MachineActivity.getFormedState(machine.peripheral)
            if type(formed) == "boolean" then
                fields.formed = formed and 1 or 0
            end

            self.influx:add("machine_activity", {
                node = self.config.node,
                mod = entry.classification.mod,
                category = entry.classification.category,
                type = entry.type,
                name = machine.name
            }, fields, timestamp)

            if idx % 10 == 0 then
                sleep(0)
            end
        end
    end
end

function Poller:collectEnergy()
    local timestamp = nowMs()
    local storages = self.discovery:getEnergyStorages()
    local totalStored = 0
    local totalCapacity = 0

    for idx, storage in ipairs(storages) do
        local status = EnergyInterface.getStatus(storage.peripheral)
        if status then
            local classification = EnergyInterface.classify(storage.name, storage.primaryType)
            totalStored = totalStored + (status.storedFE or 0)
            totalCapacity = totalCapacity + (status.capacityFE or 0)

            self.influx:add("energy_storage", {
                node = self.config.node,
                mod = classification.mod,
                type = storage.primaryType or "energy_storage",
                name = storage.name,
                storage = classification.storageType
            }, {
                stored_fe = status.storedFE,
                capacity_fe = status.capacityFE,
                percent = status.percent * 100
            }, timestamp)
        end

        if idx % 10 == 0 then
            sleep(0)
        end
    end

    if #storages > 0 then
        self.influx:add("energy_total", {
            node = self.config.node
        }, {
            stored_fe = totalStored,
            capacity_fe = totalCapacity,
            percent = totalCapacity > 0 and (totalStored / totalCapacity * 100) or 0
        }, timestamp)
    end
end

function Poller:collectAE()
    local ae = self.discovery:getAE()
    if not ae then
        return false, 0
    end

    local startMs = nowMs()
    local items = ae:items() or {}
    local fluids = ae:fluids() or {}
    local storageItems = ae:itemStorage()
    local storageFluids = ae:fluidStorage()
    local energy = ae:energy()
    local timestamp = nowMs()

    local totalItems = sumCounts(items, "count")
    local totalFluids = sumCounts(fluids, "amount")

    self.influx:add("ae_summary", {
        node = self.config.node,
        source = ae.bridgeName or "me_bridge"
    }, {
        items_total = totalItems,
        items_unique = #items,
        fluids_total = totalFluids,
        fluids_unique = #fluids,
        item_storage_used = storageItems.used,
        item_storage_total = storageItems.total,
        item_storage_available = storageItems.available,
        fluid_storage_used = storageFluids.used,
        fluid_storage_total = storageFluids.total,
        fluid_storage_available = storageFluids.available,
        energy_stored = energy.stored,
        energy_capacity = energy.capacity,
        energy_usage = energy.usage
    }, timestamp)

    sortByField(items, "count")
    sortByField(fluids, "amount")

    local itemLimit = math.min(self.config.ae_top_items or 20, #items)
    for i = 1, itemLimit do
        local item = items[i]
        self.influx:add("ae_item", {
            node = self.config.node,
            item = item.registryName
        }, {
            count = item.count
        }, timestamp)
    end

    local fluidLimit = math.min(self.config.ae_top_fluids or 10, #fluids)
    for i = 1, fluidLimit do
        local fluid = fluids[i]
        self.influx:add("ae_fluid", {
            node = self.config.node,
            fluid = fluid.registryName
        }, {
            amount = fluid.amount
        }, timestamp)
    end

    local duration = nowMs() - startMs
    return true, duration
end

function Poller:run()
    while true do
        local now = nowMs()

        if now >= self.nextMachineAt then
            self:collectMachines()
            self.nextMachineAt = now + ((self.config.machine_interval_s or 5) * 1000)
        end

        if now >= self.nextEnergyAt then
            self:collectEnergy()
            self.nextEnergyAt = now + ((self.config.energy_interval_s or 5) * 1000)
        end

        if now >= self.nextAeAt then
            local ok, duration = self:collectAE()
            if ok and duration > (self.config.ae_slow_threshold_ms or 5000) then
                self.nextAeAt = now + ((self.config.ae_slow_interval_s or 600) * 1000)
            else
                self.nextAeAt = now + ((self.config.ae_interval_s or 60) * 1000)
            end
        end

        self.influx:flushIfDue()
        sleep(0.25)
    end
end

return Poller
