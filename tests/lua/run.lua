local root = arg[1]
if not root then
    io.stderr:write("Usage: lua tests/lua/run.lua <workspace_root>\n")
    os.exit(2)
end

-- Make root available globally for spec files
_G.TEST_ROOT = root

local bootstrap = dofile(root .. "/tests/lua/bootstrap.lua")
bootstrap.bootstrap(root)

local tests = {}

_G.test = function(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function sorted(list)
    table.sort(list)
    return list
end

local specs = {}
-- Find all spec files including in subdirectories (integration tests)
local p = io.popen("find '" .. root .. "/tests/lua/specs' -type f -name '*_spec.lua' | sort")
if not p then
    io.stderr:write("Failed to enumerate specs\n")
    os.exit(2)
end

for line in p:lines() do
    specs[#specs + 1] = line
end
p:close()

-- Add mocks to package path
package.path = root .. "/tests/lua/?.lua;" .. root .. "/tests/lua/?/init.lua;" .. package.path

if #specs == 0 then
    io.stderr:write("No specs found under tests/lua/specs\n")
    os.exit(2)
end

for _, spec in ipairs(specs) do
    dofile(spec)
end

local failed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        print("[PASS] " .. t.name)
    else
        failed = failed + 1
        print("[FAIL] " .. t.name)
        print("       " .. tostring(err))
    end
end

print(string.format("Executed %d tests, %d failed", #tests, failed))
if failed > 0 then
    os.exit(1)
end
