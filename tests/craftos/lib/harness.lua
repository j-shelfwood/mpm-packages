local Harness = {}
Harness.__index = Harness

local function sorted(list)
    table.sort(list)
    return list
end

function Harness.new(workspace)
    local self = setmetatable({}, Harness)
    self.workspace = workspace
    self.tests = {}
    self.results = {
        passed = 0,
        failed = 0,
        errors = {}
    }
    self.module_cache = {}

    _G.mpm = function(name)
        if not self.module_cache[name] then
            local path = self.workspace .. "/" .. name .. ".lua"
            if not fs.exists(path) then
                error("Module not found: " .. name .. " at " .. path)
            end
            local fn, err = loadfile(path)
            if not fn then
                error("Failed to load " .. name .. ": " .. tostring(err))
            end
            self.module_cache[name] = fn()
        end
        return self.module_cache[name]
    end

    return self
end

function Harness:test(name, fn)
    self.tests[#self.tests + 1] = { name = name, fn = fn }
end

function Harness:assert_true(value, msg)
    if not value then
        error(msg or "Expected true")
    end
end

function Harness:assert_false(value, msg)
    if value then
        error(msg or "Expected false")
    end
end

function Harness:assert_eq(expected, actual, msg)
    if expected ~= actual then
        error((msg or "Values differ") .. string.format(" (expected=%s, actual=%s)", tostring(expected), tostring(actual)))
    end
end

function Harness:assert_not_nil(value, msg)
    if value == nil then
        error(msg or "Expected non-nil value")
    end
end

function Harness:assert_contains(haystack, needle, msg)
    if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
        error((msg or "String does not contain expected value") .. string.format(" (needle='%s')", tostring(needle)))
    end
end

function Harness:assert_screen_contains(driver, needle, msg)
    if not driver:contains(needle) then
        local snapshot = driver:snapshot()
        error((msg or "Screen does not contain expected text")
            .. string.format(" (needle='%s')\n--- screen ---\n%s", tostring(needle), snapshot))
    end
end

function Harness:read_file(path)
    local file, err = fs.open(path, "r")
    if not file then
        return nil, err
    end
    local content = file.readAll()
    file.close()
    return content
end

function Harness:with_overrides(target, overrides, fn)
    local original = {}
    for key, value in pairs(overrides) do
        original[key] = target[key]
        target[key] = value
    end

    local ok, result_or_err = pcall(fn)

    for key, _ in pairs(overrides) do
        target[key] = original[key]
    end

    if not ok then
        error(result_or_err)
    end
    return result_or_err
end

function Harness:with_ui_driver(width, height, fn)
    local UIDriver = dofile(self.workspace .. "/tests/craftos/lib/ui_driver.lua")
    local driver = UIDriver.new(width, height)
    local ok, result_or_err = pcall(fn, driver)
    driver:close()
    if not ok then
        error(result_or_err)
    end
    return result_or_err
end

function Harness:run()
    print("=== CraftOS Integration Scenarios ===")

    for _, t in ipairs(self.tests) do
        local ok, err = pcall(t.fn)
        if ok then
            self.results.passed = self.results.passed + 1
            print("[PASS] " .. t.name)
        else
            self.results.failed = self.results.failed + 1
            self.results.errors[#self.results.errors + 1] = { name = t.name, error = tostring(err) }
            print("[FAIL] " .. t.name)
            print("       " .. tostring(err))
        end
    end

    print("")
    print(string.format("Executed %d tests, %d failed", #self.tests, self.results.failed))

    if self.results.failed == 0 then
        print("ALL TESTS PASSED")
        return true
    end

    print("TESTS FAILED")
    return false
end

function Harness:list_scenarios(dir)
    local files = {}
    for _, name in ipairs(fs.list(dir)) do
        if name:sub(-4) == ".lua" then
            files[#files + 1] = dir .. "/" .. name
        end
    end
    return sorted(files)
end

return Harness
