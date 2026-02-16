-- CraftOS-PC CI startup entrypoint

if not fs.exists("/workspace/mpm-packages") then
    print("ERROR: /workspace not mounted")
    print("Run with: --mount-ro /workspace=<repo-root>")
    os.shutdown()
end

local ok, err = pcall(function()
    dofile("/workspace/mpm-packages/tests/craftos/runner.lua")
end)

if not ok then
    print("[FAIL] CraftOS test harness crashed")
    print("       " .. tostring(err))
    print("TESTS FAILED")
end

os.shutdown()
