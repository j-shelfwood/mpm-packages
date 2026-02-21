local KernelNetwork = mpm('shelfos/core/KernelNetwork')
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
        MachineActivity.runLoop(runningRef)
    end)

    parallel.waitForAny(table.unpack(tasks))
    kernel:shutdown()
end

return KernelDispatcher
