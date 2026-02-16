local REPO_ROOT = "/workspace"
local WORKSPACE = REPO_ROOT .. "/mpm-packages"
local SCENARIO_DIR = WORKSPACE .. "/tests/craftos/scenarios"

local Harness = dofile(WORKSPACE .. "/tests/craftos/lib/harness.lua")
local harness = Harness.new(WORKSPACE)

if not fs.exists(SCENARIO_DIR) or not fs.isDir(SCENARIO_DIR) then
    print("[FAIL] Scenario directory missing: " .. SCENARIO_DIR)
    print("TESTS FAILED")
    os.shutdown()
end

for _, scenarioPath in ipairs(harness:list_scenarios(SCENARIO_DIR)) do
    local scenario = dofile(scenarioPath)
    if type(scenario) ~= "function" then
        print("[FAIL] Scenario must return function: " .. scenarioPath)
        print("TESTS FAILED")
        os.shutdown()
    end
    scenario(harness)
end

harness:run()
os.shutdown()
