# MPM-Packages Test Suite

## Overview

This project has two test environments:

| Environment | Tests | Purpose |
|-------------|-------|---------|
| Lua 5.4 (Native) | 95 | Unit tests with mocked CC:Tweaked APIs |
| CraftOS-PC (Headless) | 22 | Integration tests with real CC:Tweaked |

## Running Tests

### All Tests (Recommended)

```bash
./tests/run_all.sh
```

### Lua Unit Tests Only

```bash
lua5.4 tests/lua/run.lua .
# or with Homebrew Lua on macOS:
/opt/homebrew/bin/lua tests/lua/run.lua .
```

### CraftOS-PC Integration Tests Only

```bash
./tests/craftos/run_tests.sh
```

## Test Structure

```
tests/
├── run_all.sh              # Unified test runner
├── README.md               # This file
├── lua/                    # Lua unit tests
│   ├── run.lua             # Test runner
│   ├── bootstrap.lua       # CC:Tweaked API stubs
│   ├── mocks/              # Peripheral mocks
│   │   ├── init.lua        # Mock framework
│   │   ├── peripheral.lua  # peripheral API
│   │   ├── rednet.lua      # rednet API (with failure simulation)
│   │   ├── modem.lua       # Modem peripheral
│   │   ├── monitor.lua     # Monitor peripheral
│   │   ├── me_bridge.lua   # ME Bridge peripheral
│   │   └── fs.lua          # Filesystem mock
│   └── specs/              # Test specifications
│       ├── pairing_spec.lua
│       ├── crypto_spec.lua
│       ├── protocol_spec.lua
│       ├── text_spec.lua
│       └── integration/    # Integration tests
│           ├── pairing_integration_spec.lua
│           ├── e2e_pairing_spec.lua
│           ├── config_pairing_spec.lua
│           ├── kernel_pairing_spec.lua
│           └── me_bridge_views_spec.lua
└── craftos/                # CraftOS-PC tests
    ├── run_tests.sh        # Shell runner
    ├── startup.lua         # CI entry point
    └── test_runner.lua     # Test harness
```

## Mock Framework

### Setting Up Mocks

```lua
local Mocks = require("mocks")

-- Setup zone computer with modem and monitors
local env = Mocks.setupZone({
    id = 10,
    label = "Zone A",
    modemName = "top",
    monitors = 2,
    meBridge = true
})

-- Setup pocket computer
local pocket = Mocks.setupPocket({
    id = 1,
    label = "Pocket"
})
```

### Simulating Network Failures

```lua
-- Fail rednet.open once
rednet._setFailMode("open_fail", 1)

-- Fail all sends forever
rednet._setFailMode("send_fail", 0)

-- Fail broadcast twice, then succeed
rednet._setFailMode("broadcast_fail", 2)
```

### Queueing Messages

```lua
-- Queue a message to be received
rednet._queueMessage(senderId, message, protocol)

-- Check broadcast log
local log = rednet._getBroadcastLog()

-- Check send log
local log = rednet._getSendLog()
```

## CraftOS-PC Integration

### Requirements

- [CraftOS-PC](https://www.craftos-pc.cc/) installed
- macOS: `/Applications/CraftOS-PC.app`

### How It Works

1. CraftOS-PC runs in `--headless` mode
2. Workspace mounted read-only at `/workspace`
3. Test harness loads modules via `mpm()` loader
4. Tests use real CC:Tweaked APIs (os.pullEvent, parallel, etc.)

### Key CLI Flags

```bash
craftos --headless \
    --mount-ro /workspace=/path/to/mpm-packages \
    --exec "dofile('/workspace/tests/craftos/test_runner.lua')"
```

## CI/CD

GitHub Actions workflow runs both test suites:

1. **lua-tests**: Ubuntu + Lua 5.4
2. **craftos-tests**: CraftOS-PC Action

See `.github/workflows/test.yml` for configuration.

## Writing Tests

### Lua Unit Test

```lua
test("My feature works", function()
    local MyModule = mpm("path/to/MyModule")

    local result = MyModule.doSomething()

    assert_eq("expected", result)
    assert_true(result ~= nil)
    assert_false(result == false)
end)
```

### CraftOS-PC Integration Test

```lua
test("Real CC:Tweaked API works", function()
    setup_mpm()

    -- Use real CC:Tweaked APIs
    local timerId = os.startTimer(0.1)
    local event, id = os.pullEvent("timer")

    assert_eq("timer", event)
    assert_eq(timerId, id)
end)
```

## Coverage

### Pairing Module (25 tests)

- Happy path flows
- Timeout handling
- User cancellation
- Modem error paths
- Credential format variations
- State machine edges
- Network failure simulation
- Security (wrong code rejection)

### Crypto Module (4 tests)

- Secret generation
- Sign/verify roundtrip
- Ephemeral key operations
- Replay attack prevention

### Protocol Module (4 tests)

- Message structure validation
- Request/response classification

### Views (10 tests)

- Mount conditions
- Rendering with mocked data
