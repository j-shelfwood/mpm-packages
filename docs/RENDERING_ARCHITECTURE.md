# ShelfOS Rendering Architecture

## Overview

ShelfOS uses **window buffering** for flicker-free multi-monitor rendering. This document explains the pattern and provides guidelines for view development.

## The Problem

Direct monitor rendering causes two critical issues:

1. **Flashing**: Calling `monitor.clear()` on every render tick causes visible flicker as the screen goes black momentarily before being redrawn.

2. **Single-monitor rendering**: Calling `Yield.yield()` or `os.sleep()` during render causes context switching. In a single-threaded event loop, this allows other monitors' timers to fire before the current render completes, causing only one monitor to appear rendered at a time.

## The Solution: Window Buffering

Per [CC:Tweaked Window API](https://tweaked.cc/module/window.html) best practices:

```
Windows retain a memory of everything rendered "through" them (hence acting
as display buffers), and if the parent's display is wiped, the window's
content can be easily redrawn later. A window may also be flagged as invisible,
preventing any changes to it from being rendered until it's flagged as visible
once more.
```

### Architecture

ShelfOS uses a **two-phase render** to allow yielding in `getData()` without blocking other monitors:

```
┌─────────────────────────────────────────────────────────────┐
│                        Monitor.lua                          │
├─────────────────────────────────────────────────────────────┤
│  self.peripheral = peripheral.wrap(name)   -- raw monitor  │
│  self.buffer = window.create(peripheral, 1, 1, w, h, true) │
│                                                             │
│  render():                                                  │
│    ─── PHASE 1: Data Fetch (buffer VISIBLE) ───            │
│    1. data = view.getData(viewInstance)  -- CAN yield here │
│       (Other monitors can fire/render during yields)       │
│                                                             │
│    ─── PHASE 2: Draw (buffer HIDDEN) ───                   │
│    2. buffer.setVisible(false)  -- hide during render      │
│    3. buffer.clear()            -- clear invisible buffer  │
│    4. view.renderWithData(viewInstance, data)  -- NO yield │
│    5. buffer.setVisible(true)   -- atomic flip (instant!)  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         View (BaseView)                     │
├─────────────────────────────────────────────────────────────┤
│  self.monitor = buffer  -- receives window, not peripheral │
│                                                             │
│  getData(self):         -- PHASE 1: Can yield freely       │
│    local items = self.interface:items()                    │
│    Yield.yield()        -- OK here!                        │
│    return processed_data                                    │
│                                                             │
│  renderWithData(self, data):  -- PHASE 2: No yields!       │
│    -- DO NOT call self.monitor.clear()                      │
│    -- DO NOT call Yield.yield()                             │
│    -- Just draw content directly                            │
└─────────────────────────────────────────────────────────────┘
```

### Why Two Phases?

The key insight: **yielding while the buffer is hidden blocks other monitors**.

In CC:Tweaked's single-threaded event loop, `yield()` allows other coroutines (timers for other monitors) to run. If a monitor yields while its buffer is hidden, the user sees a blank screen during that time.

By splitting into two phases:
1. **getData()** can yield freely while buffer is visible (showing previous frame)
2. **renderWithData()** runs without yields while buffer is hidden (fast atomic update)

## Rules for View Development

### DO NOT in render():

```lua
-- WRONG: Causes flashing
function render(self, data)
    self.monitor.clear()  -- NO! Buffer handles this
    -- ...
end

-- WRONG: Causes context switching
function render(self, data)
    -- draw something
    Yield.yield()  -- NO! Breaks multi-monitor
    -- draw more
end

-- WRONG: Causes resize events
function render(self, data)
    self.monitor.setTextScale(0.5)  -- NO! Monitor.lua sets scale once
    -- ...
end
```

### DO in render():

```lua
-- CORRECT: Just draw content
function render(self, data)
    self.monitor.setBackgroundColor(colors.black)
    self.monitor.setTextColor(colors.white)
    -- Draw directly - buffer is already cleared
    self.monitor.setCursorPos(1, 1)
    self.monitor.write("Content")
end
```

### Yielding in getData():

Yielding is acceptable (and encouraged for large data processing) inside `getData()`:

```lua
getData = function(self)
    local items = self.interface:items()
    Yield.yield()  -- OK here - not in render path

    local filtered = Yield.filter(items, function(item)
        return item.count > 0
    end)

    return filtered
end
```

## Component Responsibilities

### Monitor.lua
- Creates and manages window buffer
- Sets text scale ONCE at initialization
- Handles buffer visibility toggling
- Clears buffer before each render
- Passes buffer (not peripheral) to views

### BaseView.lua
- Provides declarative view framework
- Exposes two-phase API for Monitor.lua:
  - `getData(self)` - Phase 1, can yield
  - `renderWithData(self, data)` - Phase 2, no yields
  - `renderError(self, errorMsg)` - Error state display
- Also provides legacy `render()` for non-ShelfOS usage
- Does NOT clear monitor
- Does NOT yield in render path

### GridDisplay.lua
- Renders grid layouts to buffer
- Does NOT change text scale
- Does NOT clear by default (`skipClear=true`)
- Uses cached scale values

### Views (individual)
- Define `getData()` for data fetching (can yield)
- Define `render()` for drawing (no clear, no yield)
- Define `formatItem()` for grid/list formatting

## Viewport Slicing (MANDATORY)

`renderWithData()` runs with the buffer HIDDEN and MUST NOT yield. This means it must be
**O(1) relative to total inventory size** — iterating over 50,000 items while the buffer
is hidden causes a CPU Watchdog crash.

**The fix: slice arrays in `getData()` before returning.**

```lua
-- getData() - Phase 1 (buffer visible, can yield freely)
getData = function(self)
    local allItems = self.interface:items()  -- may be 50,000 items

    -- Sort here (can be slow, we're in Phase 1)
    table.sort(allItems, ...)

    -- MANDATORY: slice to visible capacity before Phase 2
    local maxVisible = self.width * self.height  -- worst-case upper bound
    local maxItems = math.min(#allItems, 100)    -- or your view's configured cap
    local sliced = {}
    for i = 1, maxItems do
        sliced[i] = allItems[i]
    end
    return sliced  -- renderWithData only iterates 100 items max
end,

-- renderWithData() - Phase 2 (buffer HIDDEN, no yields, no large loops)
renderWithData = function(self, data)
    -- data is already sliced - safe to iterate
    for i, item in ipairs(data) do
        -- draw item...
    end
end
```

**Hard limits enforced by the framework:**
- `ListFactory` (ItemList, FluidList, ChemicalList): slices to `maxItems` (default 100) in `getData()`
- `renderGrid` in BaseViewRenderers: caps at `def.maxItems or 50` as a safety net
- Any custom `getData()` that returns a large array MUST slice it first

## Text Scale Management

Text scale is managed ONCE by `Monitor.lua` during initialization:

```lua
-- Monitor.lua
function Monitor:initialize()
    self.currentScale, self.bufferWidth, self.bufferHeight = calculateTextScale(self.peripheral)
    self.buffer = window.create(self.peripheral, 1, 1, self.bufferWidth, self.bufferHeight, true)
end
```

Views and GridDisplay should NEVER call `setTextScale()`. The dimensions are fixed when the buffer is created.

## Interactive Menus (Exception)

Config menus (view selector, settings) use the raw peripheral directly because they need immediate visual feedback for touch interactions:

```lua
-- Monitor.lua - openConfigMenu()
function Monitor:drawConfigMenu()
    -- Uses self.peripheral (not self.buffer) for interactive menus
    local List = mpm('ui/List')
    local selected = List.new(self.peripheral, self.availableViews, {...})
end
```

After the menu closes, `closeConfigMenu()` triggers a buffered render to restore normal operation.

## Debugging Flicker Issues

If you see flashing:

1. **Check for `clear()` calls**: Search for `monitor.clear()` or `self.monitor.clear()` in view code
2. **Check for yields in render**: Search for `Yield.yield()` between draw calls
3. **Check for scale changes**: Search for `setTextScale()` in view code
4. **Verify buffer is used**: Ensure `Monitor:loadView()` passes `self.buffer` not `self.peripheral`

## References

- [CC:Tweaked Window API](https://tweaked.cc/module/window.html)
- [CC:Tweaked Monitor Peripheral](https://tweaked.cc/peripheral/monitor.html)
- [Monitor Rendering Blog Post](https://squiddev.cc/2023/03/18/monitors-again.html)
