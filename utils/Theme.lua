-- Theme.lua
-- Monitor palette theming for CC:Tweaked
-- Allows customization of the 16-color palette

local Theme = {}

-- Theme presets
-- Each theme maps color constants to 24-bit RGB values
Theme.presets = {
    -- Default: use CC:Tweaked built-in palette
    default = {},

    -- Dark theme: darker grays, muted colors
    dark = {
        [colors.gray] = 0x1a1a1a,
        [colors.lightGray] = 0x333333,
        [colors.blue] = 0x0066cc,
        [colors.lightBlue] = 0x3399ff,
    },

    -- High contrast: maximum readability
    highContrast = {
        [colors.gray] = 0x404040,
        [colors.lightGray] = 0xc0c0c0,
        [colors.white] = 0xffffff,
        [colors.black] = 0x000000,
    },

    -- Solarized dark theme
    solarized = {
        [colors.black] = 0x002b36,
        [colors.gray] = 0x073642,
        [colors.lightGray] = 0x586e75,
        [colors.white] = 0xfdf6e3,
        [colors.yellow] = 0xb58900,
        [colors.orange] = 0xcb4b16,
        [colors.red] = 0xdc322f,
        [colors.magenta] = 0xd33682,
        [colors.purple] = 0x6c71c4,
        [colors.blue] = 0x268bd2,
        [colors.cyan] = 0x2aa198,
        [colors.green] = 0x859900,
    },

    -- Monokai theme
    monokai = {
        [colors.black] = 0x272822,
        [colors.gray] = 0x3e3d32,
        [colors.lightGray] = 0x75715e,
        [colors.white] = 0xf8f8f2,
        [colors.red] = 0xf92672,
        [colors.orange] = 0xfd971f,
        [colors.yellow] = 0xe6db74,
        [colors.green] = 0xa6e22e,
        [colors.cyan] = 0x66d9ef,
        [colors.blue] = 0x66d9ef,
        [colors.purple] = 0xae81ff,
        [colors.magenta] = 0xf92672,
    },
}

-- Get list of available theme names
function Theme.list()
    local names = {}
    for name in pairs(Theme.presets) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Check if a theme exists
function Theme.exists(themeName)
    return Theme.presets[themeName] ~= nil
end

-- Apply a theme to a monitor
-- @param monitor The monitor peripheral
-- @param themeName Theme name from presets (default: "default")
function Theme.apply(monitor, themeName)
    if not monitor or not monitor.setPaletteColor then
        return false
    end

    themeName = themeName or "default"
    local theme = Theme.presets[themeName]

    if not theme then
        return false
    end

    -- If default theme, reset to native colors
    if themeName == "default" or not next(theme) then
        Theme.reset(monitor)
        return true
    end

    -- Apply custom palette colors
    for color, rgb in pairs(theme) do
        monitor.setPaletteColor(color, rgb)
    end

    return true
end

-- Reset monitor palette to native CC:Tweaked defaults
-- @param monitor The monitor peripheral
function Theme.reset(monitor)
    if not monitor or not monitor.setPaletteColor then
        return false
    end

    -- Iterate through all 16 colors and reset to native
    for i = 0, 15 do
        local color = 2 ^ i
        -- Get native palette from term (monitors don't have nativePaletteColor)
        local r, g, b = term.nativePaletteColor(color)
        monitor.setPaletteColor(color, r, g, b)
    end

    return true
end

-- Get current palette from a monitor
-- @param monitor The monitor peripheral
-- @return table mapping color constants to RGB values
function Theme.getCurrentPalette(monitor)
    if not monitor or not monitor.getPaletteColor then
        return nil
    end

    local palette = {}
    for i = 0, 15 do
        local color = 2 ^ i
        local r, g, b = monitor.getPaletteColor(color)
        -- Convert to 24-bit RGB
        palette[color] = math.floor(r * 255) * 0x10000
                       + math.floor(g * 255) * 0x100
                       + math.floor(b * 255)
    end

    return palette
end

-- Add a custom theme preset
-- @param name Theme name
-- @param palette Table mapping color constants to RGB values
function Theme.addPreset(name, palette)
    if type(name) == "string" and type(palette) == "table" then
        Theme.presets[name] = palette
        return true
    end
    return false
end

return Theme
