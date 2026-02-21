local KernelNetwork = mpm('shelfos/core/KernelNetwork')
local AESnapshotBus = mpm('peripherals/AESnapshotBus')
local MachineSnapshotBus = mpm('peripherals/MachineSnapshotBus')
local EnergySnapshotBus = mpm('peripherals/EnergySnapshotBus')
local MekSnapshotBus = mpm('peripherals/MekSnapshotBus')
local GenericInventorySnapshotBus = mpm('peripherals/GenericInventorySnapshotBus')
local MachineActivity = mpm('peripherals/MachineActivity')

local KernelDispatcher = {}

function KernelDispatcher.run(kernel)
    local runningRef = { value = true }
    local tasks = {}

    for _, monitor in ipairs(kernel.monitors) do
        table.insert(tasks, function()
            monitor:runLoop(runningRef)
        end)
    end

    table.insert(tasks, function()
        kernel:keyboardLoop(runningRef)
    end)

    table.insert(tasks, function()
        kernel:dashboardLoop(runningRef)
    end)

    table.insert(tasks, function()
        KernelNetwork.loop(kernel, runningRef)
    end)

    table.insert(tasks, function()
        AESnapshotBus.runLoop(runningRef)
    end)

    table.insert(tasks, function()
        MachineSnapshotBus.runLoop(runningRef)
    end)

    table.insert(tasks, function()
        EnergySnapshotBus.runLoop(runningRef)
    end)

    table.insert(tasks, function()
        MekSnapshotBus.runLoop(runningRef)
    end)

    table.insert(tasks, function()
        GenericInventorySnapshotBus.runLoop(runningRef)
    end)

    table.insert(tasks, function()
        MachineActivity.runLoop(runningRef)
    end)

    parallel.waitForAny(table.unpack(tasks))
    kernel:shutdown()
end

return KernelDispatcher
