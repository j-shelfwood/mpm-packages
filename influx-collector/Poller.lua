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
    self.onEvent = nil
    self.stats = {
        machines  = { count = 0, duration_ms = 0, last_at = 0, active = false, burst = false, active_count = 0 },
        energy    = { count = 0, duration_ms = 0, last_at = 0 },
        detectors = { count = 0, duration_ms = 0, last_at = 0, active = false, burst = false },
        ae        = { items = 0, fluids = 0, chemicals = 0, duration_ms = 0, last_at = 0,
                      connected = false, online = false, cpu_total = 0, cpu_busy = 0, task_count = 0 },
        inventory = { items = 0, fluids = 0, chemicals = 0, last_at = 0, duration_ms = 0 }
    }
    -- nil = not yet probed; true/false set after first discovery attempt
    self.present = {
        machines  = nil,
        energy    = nil,
        detectors = nil,
        ae        = nil,
    }
    self.lastMachinesActiveAt = 0
    self.lastDetectorsActiveAt = 0
    self.nextMachineAt    = 0
    self.nextEnergyAt     = 0
    self.nextDetectorAt   = 0
    self.nextAeAt         = 0
    self.nextInventoryAt  = 0
    return self
end

function Poller:setEventSink(fn)
    self.onEvent = fn
end

function Poller:emit(kind, data)
    if self.onEvent then
        pcall(self.onEvent, kind, data)
    else
        pcall(os.queueEvent, "collector_event", { kind = kind, data = data })
    end
end

function Poller:getSchedule()
    return {
        nextMachineAt   = self.nextMachineAt,
        nextEnergyAt    = self.nextEnergyAt,
        nextDetectorAt  = self.nextDetectorAt,
        nextAeAt        = self.nextAeAt,
        nextInventoryAt = self.nextInventoryAt,
        machineBurst    = self:isMachineBurstActive(),
        detectorBurst   = self:isDetectorBurstActive(),
        present         = self.present,
    }
end

function Poller:isMachineBurstActive()
    if not self.lastMachinesActiveAt or self.lastMachinesActiveAt == 0 then
        return false
    end
    local windowMs = (self.config.machine_burst_window_s or 10) * 1000
    return (nowMs() - self.lastMachinesActiveAt) <= windowMs
end

function Poller:isDetectorBurstActive()
    if not self.lastDetectorsActiveAt or self.lastDetectorsActiveAt == 0 then
        return false
    end
    local windowMs = (self.config.energy_detector_burst_window_s or 10) * 1000
    return (nowMs() - self.lastDetectorsActiveAt) <= windowMs
end

function Poller:collectMachines()
    local startMs = nowMs()
    local timestamp = nowMs()
    local machineTypes = self.discovery:getMachines()
    self.present.machines = #machineTypes > 0
    if not self.present.machines then
        self.stats.machines = { count = 0, duration_ms = 0, last_at = 0, active = false, burst = false, active_count = 0 }
        return
    end
    local totalMachines = 0
    local activeDetected = false
    local activeCount = 0
    local uniqueMods = {}

    -- Per-machine activity write; accumulate per-type active counts in one pass
    for _, entry in ipairs(machineTypes) do
        local typeTotal = #entry.machines
        totalMachines = totalMachines + typeTotal
        uniqueMods[entry.classification.mod] = true
        local typeActive = 0

        for idx, machine in ipairs(entry.machines) do
            local active, data = MachineActivity.getActivity(machine.peripheral)
            if active then
                activeDetected = true
                activeCount = activeCount + 1
                typeActive = typeActive + 1
            end

            local fields = { active = active and 1 or 0 }
            if type(data.progress) == "number" then fields.progress = data.progress end
            if type(data.total) == "number" then fields.progress_total = data.total end
            if type(data.percent) == "number" then fields.progress_percent = data.percent end
            if type(data.rate) == "number" then fields.production_rate = data.rate end
            if type(data.usage) == "number" then fields.energy_usage = data.usage end

            local energyPercent = MachineActivity.getEnergyPercent(machine.peripheral)
            if type(energyPercent) == "number" then fields.energy_percent = energyPercent * 100 end

            local formed = MachineActivity.getFormedState(machine.peripheral)
            if type(formed) == "boolean" then fields.formed = formed and 1 or 0 end

            self.influx:add("machine_activity", {
                node     = self.config.node,
                mod      = entry.classification.mod,
                category = entry.classification.category,
                type     = entry.type,
                name     = machine.name
            }, fields, timestamp)

            if idx % 10 == 0 then sleep(0) end
        end

        -- Per-type rollup (no second poll — reuses typeActive from above)
        if typeTotal > 0 then
            self.influx:add("machine_type", {
                node     = self.config.node,
                mod      = entry.classification.mod,
                category = entry.classification.category,
                type     = entry.type
            }, {
                total_count    = typeTotal,
                active_count   = typeActive,
                active_percent = typeActive / typeTotal * 100
            }, timestamp)
        end
    end

    if activeDetected then
        self.lastMachinesActiveAt = timestamp
    end

    -- Node-level summary across all types
    if totalMachines > 0 then
        local modCount = 0
        for _ in pairs(uniqueMods) do modCount = modCount + 1 end
        self.influx:add("machine_summary", {
            node = self.config.node
        }, {
            total_machines  = totalMachines,
            active_machines = activeCount,
            active_percent  = activeCount / totalMachines * 100,
            unique_types    = #machineTypes,
            unique_mods     = modCount
        }, timestamp)
    end

    self.stats.machines = {
        count = totalMachines,
        duration_ms = nowMs() - startMs,
        last_at = timestamp,
        active = activeDetected,
        burst = self:isMachineBurstActive(),
        active_count = activeCount
    }
    self:emit("machines", self.stats.machines)
end

function Poller:collectEnergyDetectors()
    local startMs = nowMs()
    local timestamp = nowMs()
    local detectors = self.discovery:getEnergyDetectors()
    self.present.detectors = #detectors > 0
    if not self.present.detectors then
        self.stats.detectors = { count = 0, duration_ms = 0, last_at = 0, active = false, burst = false }
        return
    end
    local activeDetected = false

    for idx, entry in ipairs(detectors) do
        local rateOk, rate = pcall(entry.peripheral.getTransferRate)
        local limitOk, limit = pcall(entry.peripheral.getTransferRateLimit)
        if rateOk and type(rate) == "number" then
            if rate > 0 then
                activeDetected = true
            end
            local fields = { rate_fe_t = rate }
            if limitOk and type(limit) == "number" then
                fields.limit_fe_t = limit
            end
            self.influx:add("energy_flow", {
                node = self.config.node,
                name = entry.name
            }, fields, timestamp)
        end

        if idx % 10 == 0 then
            sleep(0)
        end
    end

    if activeDetected then
        self.lastDetectorsActiveAt = timestamp
    end

    self.stats.detectors = {
        count = #detectors,
        duration_ms = nowMs() - startMs,
        last_at = timestamp,
        active = activeDetected,
        burst = self:isDetectorBurstActive()
    }
    self:emit("detectors", self.stats.detectors)
end

function Poller:collectEnergy()
    local startMs = nowMs()
    local timestamp = nowMs()
    local storages = self.discovery:getEnergyStorages()
    self.present.energy = #storages > 0
    if not self.present.energy then
        self.stats.energy = { count = 0, duration_ms = 0, last_at = 0 }
        return
    end
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

    self.stats.energy = {
        count = #storages,
        duration_ms = nowMs() - startMs,
        last_at = timestamp
    }
    self:emit("energy", self.stats.energy)
end

function Poller:collectAE()
    local ae = self.discovery:getAE()
    local disconnected = {
        items = 0, fluids = 0, chemicals = 0, duration_ms = 0,
        last_at = 0, connected = false, online = false,
        cpu_total = 0, cpu_busy = 0, task_count = 0
    }
    if not ae then
        self.present.ae = false
        self.stats.ae = disconnected
        self:emit("ae", self.stats.ae)
        return false, 0
    end
    self.present.ae = true

    local conn = ae.getConnectionStatus and ae:getConnectionStatus() or { isConnected = false, isOnline = false }
    if not conn.isConnected then
        disconnected.last_at = nowMs()
        disconnected.connected = conn.isConnected
        disconnected.online = conn.isOnline
        self.stats.ae = disconnected
        self:emit("ae", self.stats.ae)
        return false, 0
    end

    local startMs = nowMs()
    local src = ae.bridgeName or "me_bridge"
    local node = self.config.node

    -- Storage and energy
    local items        = ae:items() or {}
    local fluids       = ae:fluids() or {}
    local chemicals    = ae:chemicals() or {}
    local storageItems = ae:itemStorage()
    local storageFluids = ae:fluidStorage()
    local energy       = ae:energy()
    local energyInput  = ae:getAverageEnergyInput() or 0

    -- Crafting CPUs
    local cpus = ae:getCraftingCPUs() or {}
    local cpuTotal = #cpus
    local cpuBusy = 0
    for _, cpu in ipairs(cpus) do
        if cpu.isBusy then cpuBusy = cpuBusy + 1 end
    end

    -- Per-CPU detail
    for _, cpu in ipairs(cpus) do
        local cpuName = (type(cpu.name) == "string" and cpu.name ~= "") and cpu.name or "unnamed"
        self.influx:add("ae_cpu", {
            node   = node,
            source = src,
            cpu    = cpuName
        }, {
            storage      = type(cpu.storage) == "number" and cpu.storage or 0,
            co_processors = type(cpu.coProcessors) == "number" and cpu.coProcessors or 0,
            is_busy      = cpu.isBusy and 1 or 0
        }, startMs)
    end

    -- CPU fleet summary
    if cpuTotal > 0 then
        self.influx:add("ae_crafting_cpu", {
            node   = node,
            source = src
        }, {
            total        = cpuTotal,
            busy         = cpuBusy,
            busy_percent = cpuBusy / cpuTotal * 100
        }, startMs)
    end

    -- Active crafting tasks — per-item detail
    local tasks = ae:getCraftingTasks() or {}
    for _, task in ipairs(tasks) do
        local res = type(task.resource) == "table" and task.resource or {}
        local itemName = res.name or "unknown"
        local cpuName = (type(task.cpu) == "table" and type(task.cpu.name) == "string" and task.cpu.name ~= "")
                         and task.cpu.name or "unknown"
        self.influx:add("ae_crafting_job", {
            node   = node,
            source = src,
            item   = itemName,
            cpu    = cpuName
        }, {
            quantity   = type(task.quantity) == "number" and task.quantity or 0,
            crafted    = type(task.crafted) == "number" and task.crafted or 0,
            completion = type(task.completion) == "number" and task.completion * 100 or 0
        }, startMs)
    end

    -- Crafting task count summary
    self.influx:add("ae_crafting_task", {
        node   = node,
        source = src
    }, {
        count = #tasks
    }, startMs)

    -- AE network summary
    local totalItems   = sumCounts(items, "count")
    local totalFluids  = sumCounts(fluids, "amount")
    local totalChemicals = sumCounts(chemicals, "amount")

    local summaryFields = {
        items_total            = totalItems,
        items_unique           = #items,
        fluids_total           = totalFluids,
        fluids_unique          = #fluids,
        item_storage_used      = storageItems.used,
        item_storage_total     = storageItems.total,
        item_storage_available = storageItems.available,
        fluid_storage_used     = storageFluids.used,
        fluid_storage_total    = storageFluids.total,
        fluid_storage_available = storageFluids.available,
        energy_stored          = energy.stored,
        energy_capacity        = energy.capacity,
        energy_usage           = energy.usage,
        energy_input           = energyInput
    }

    -- Add chemical storage if the bridge supports it
    if ae:hasChemicalSupport() then
        summaryFields.chemicals_total   = totalChemicals
        summaryFields.chemicals_unique  = #chemicals
        local chemStorage = ae:getStorage("chemicals", false)
        if chemStorage then
            summaryFields.chemical_storage_used      = chemStorage.used
            summaryFields.chemical_storage_total     = chemStorage.total
            summaryFields.chemical_storage_available = chemStorage.available
        end
    end

    self.influx:add("ae_summary", { node = node, source = src }, summaryFields, startMs)

    -- All items (top N by count for ordering, but all are written)
    sortByField(items, "count")
    for i = 1, #items do
        local item = items[i]
        self.influx:add("ae_item", {
            node = node,
            item = item.registryName
        }, { count = item.count }, startMs)
        if i % 10 == 0 then sleep(0) end
    end

    -- All fluids
    for i, fluid in ipairs(fluids) do
        self.influx:add("ae_fluid", {
            node  = node,
            fluid = fluid.registryName
        }, { amount = fluid.amount }, startMs)
        if i % 10 == 0 then sleep(0) end
    end

    -- All chemicals
    if ae:hasChemicalSupport() and #chemicals > 0 then
        for i, chem in ipairs(chemicals) do
            self.influx:add("ae_chemical", {
                node     = node,
                chemical = chem.registryName
            }, { amount = chem.amount }, startMs)
            if i % 10 == 0 then sleep(0) end
        end
    end

    local duration = nowMs() - startMs
    self.stats.ae = {
        items      = #items,
        fluids     = #fluids,
        chemicals  = #chemicals,
        duration_ms = duration,
        last_at    = startMs,
        connected  = conn.isConnected,
        online     = conn.isOnline,
        cpu_total  = cpuTotal,
        cpu_busy   = cpuBusy,
        task_count = #tasks
    }
    self:emit("ae", self.stats.ae)
    return true, duration
end

-- Full inventory snapshot — all items, fluids, chemicals.
-- Runs on a slow timer (default 10 min). Writes one line per unique item/fluid/chemical.
-- Tagged with snapshot=true so dashboards can distinguish from rolling top-N data.
function Poller:collectInventory()
    local ae = self.discovery:getAE()
    if not ae then return end

    local conn = ae.getConnectionStatus and ae:getConnectionStatus() or { isConnected = false }
    if not conn.isConnected then return end

    local startMs = nowMs()
    local node = self.config.node
    local src  = ae.bridgeName or "me_bridge"

    local items     = ae:items() or {}
    local fluids    = ae:fluids() or {}
    local chemicals = ae:hasChemicalSupport() and (ae:chemicals() or {}) or {}

    for i, item in ipairs(items) do
        self.influx:add("inventory_item", {
            node = node,
            item = item.registryName
        }, {
            count      = item.count,
            craftable  = item.isCraftable and 1 or 0
        }, startMs)
        if i % 10 == 0 then sleep(0) end
    end

    for i, fluid in ipairs(fluids) do
        self.influx:add("inventory_fluid", {
            node  = node,
            fluid = fluid.registryName
        }, { amount = fluid.amount }, startMs)
        if i % 10 == 0 then sleep(0) end
    end

    for i, chem in ipairs(chemicals) do
        self.influx:add("inventory_chemical", {
            node     = node,
            chemical = chem.registryName
        }, { amount = chem.amount }, startMs)
        if i % 10 == 0 then sleep(0) end
    end

    local duration = nowMs() - startMs
    self.stats.inventory = {
        items      = #items,
        fluids     = #fluids,
        chemicals  = #chemicals,
        last_at    = startMs,
        duration_ms = duration
    }
    self:emit("inventory", self.stats.inventory)
end

-- How long to wait before re-probing a peripheral type that wasn't found (ms).
local ABSENT_RECHECK_MS = 60 * 1000

function Poller:run()
    while true do
        local now = nowMs()

        if now >= self.nextMachineAt then
            self:collectMachines()
            if not self.present.machines then
                self.nextMachineAt = now + ABSENT_RECHECK_MS
            else
                local interval = self.config.machine_interval_s or 5
                if self:isMachineBurstActive() then
                    interval = self.config.machine_burst_interval_s or interval
                end
                self.nextMachineAt = now + (interval * 1000)
            end
        end

        if now >= self.nextEnergyAt then
            self:collectEnergy()
            if not self.present.energy then
                self.nextEnergyAt = now + ABSENT_RECHECK_MS
            else
                self.nextEnergyAt = now + ((self.config.energy_interval_s or 5) * 1000)
            end
        end

        if now >= self.nextDetectorAt then
            self:collectEnergyDetectors()
            if not self.present.detectors then
                self.nextDetectorAt = now + ABSENT_RECHECK_MS
            else
                local interval = self.config.energy_detector_interval_s or self.config.energy_interval_s or 5
                if self:isDetectorBurstActive() then
                    interval = self.config.energy_detector_burst_interval_s or interval
                end
                self.nextDetectorAt = now + (interval * 1000)
            end
        end

        if now >= self.nextAeAt then
            local ok, duration = self:collectAE()
            if not self.present.ae then
                self.nextAeAt = now + ABSENT_RECHECK_MS
            elseif ok and duration > (self.config.ae_slow_threshold_ms or 5000) then
                self.nextAeAt = now + ((self.config.ae_slow_interval_s or 600) * 1000)
            else
                self.nextAeAt = now + ((self.config.ae_interval_s or 60) * 1000)
            end
        end

        if now >= self.nextInventoryAt then
            -- inventory piggybacks on AE; skip entirely if AE not present
            if self.present.ae ~= false then
                self:collectInventory()
            end
            if not self.present.ae then
                self.nextInventoryAt = now + ABSENT_RECHECK_MS
            else
                self.nextInventoryAt = now + ((self.config.inventory_interval_s or 600) * 1000)
            end
        end

        self.influx:flushIfDue()
        sleep(0.25)
    end
end

return Poller
