local KernelNetwork = mpm('shelfos/core/KernelNetwork')

local KernelDispatcher = {}

local function guardedTask(label, fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            print("[ShelfOS] Task crashed (" .. label .. "): " .. tostring(err))
        end
    end
end

function KernelDispatcher.run(kernel)
    local runningRef = { value = true }
    local tasks = {}

    for _, monitor in ipairs(kernel.monitors) do
        local m = monitor
        table.insert(tasks, guardedTask(
            "monitor:" .. (m.peripheralName or "unknown"),
            function() m:runLoop(runningRef) end
        ))
    end

    table.insert(tasks, guardedTask("keyboard", function()
        kernel:keyboardLoop(runningRef)
    end))

    table.insert(tasks, guardedTask("dashboard", function()
        kernel:dashboardLoop(runningRef)
    end))

    table.insert(tasks, guardedTask("network", function()
        KernelNetwork.loop(kernel, runningRef)
    end))

    parallel.waitForAny(table.unpack(tasks))
    kernel:shutdown()
end

return KernelDispatcher
