-- RenderContext.lua
-- Tracks which monitor/view context is currently fetching data.
-- Used by remote peripheral proxies to attribute network calls to a view.

local RenderContext = {}

_G._shelfos_renderContext = _G._shelfos_renderContext or {
    current = nil
}

function RenderContext.set(contextKey)
    _G._shelfos_renderContext.current = contextKey
end

function RenderContext.get()
    return _G._shelfos_renderContext.current
end

function RenderContext.clear()
    _G._shelfos_renderContext.current = nil
end

return RenderContext
