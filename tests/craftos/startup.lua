-- CraftOS-PC CI Startup Script
-- This runs when CraftOS-PC starts in CI environment
-- Mounts the workspace and runs tests

-- Check for workspace mount
if not fs.exists("/workspace") then
    print("ERROR: /workspace not mounted")
    print("Run with: --mount-ro /workspace=<mpm-packages-path>")
    os.shutdown()
end

-- Run test harness
local ok, err = pcall(function()
    dofile("/workspace/tests/craftos/test_runner.lua")
end)

if not ok then
    print("")
    print("TEST HARNESS ERROR:")
    print(tostring(err))
    print("")
    print("TESTS FAILED")
end

os.shutdown()
