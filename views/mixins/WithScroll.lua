local Renderers = mpm('views/BaseViewRenderers')

local WithScroll = {}

function WithScroll.initialize(instance)
    instance._scrollOffset = instance._scrollOffset or 0
    instance._pageSize = instance._pageSize
    instance._touchZones = instance._touchZones or {}
    instance._data = instance._data
end

function WithScroll.handleTouch(instance, x, y, onItemTouch)
    return Renderers.handleInteractiveTouch(instance, x, y, onItemTouch)
end

function WithScroll.getState(instance)
    return {
        scrollOffset = instance._scrollOffset or 0,
        pageSize = instance._pageSize
    }
end

function WithScroll.setState(instance, state)
    if not state then
        return
    end

    instance._scrollOffset = state.scrollOffset or 0
    if state.pageSize then
        instance._pageSize = state.pageSize
    end
end

return WithScroll
