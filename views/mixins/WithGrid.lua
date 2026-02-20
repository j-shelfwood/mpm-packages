local Renderers = mpm('views/BaseViewRenderers')

local WithGrid = {}

function WithGrid.render(view, data, formatItem, startY, definition)
    Renderers.renderGrid(view, data, formatItem, startY, definition)

    if definition.header then
        local header = definition.header(view, data)
        Renderers.renderHeader(view, header)
    end
end

return WithGrid
