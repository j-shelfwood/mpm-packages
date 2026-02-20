return function(h)
    h:test("README contract: shelfos README exists", function()
        local path = h.workspace .. "/shelfos/README.md"
        h:assert_true(fs.exists(path), "README missing at " .. path)
        h:assert_false(fs.isDir(path), "README path is directory")
    end)

    h:test("README contract: onboarding commands are documented", function()
        local content, err = h:read_file(h.workspace .. "/shelfos/README.md")
        h:assert_not_nil(content, "Failed to read README: " .. tostring(err))

        h:assert_contains(content, "mpm run shelfos", "README missing shelfos run command")
        h:assert_contains(content, "mpm run shelfos-swarm", "README missing shelfos-swarm run command")
        h:assert_contains(content, "Accept from pocket", "README missing pocket accept flow")
        h:assert_contains(content, "Setting Up Your Swarm", "README missing swarm setup section")
    end)

    h:test("README contract: documented pairing entrypoints exist", function()
        h:assert_true(fs.exists(h.workspace .. "/shelfos/start.lua"), "shelfos start.lua missing")
        h:assert_true(fs.exists(h.workspace .. "/shelfos-swarm/start.lua"), "shelfos-swarm start.lua missing")
        h:assert_true(fs.exists(h.workspace .. "/shelfos/core/KernelPairing.lua"), "KernelPairing module missing")
    end)
end
