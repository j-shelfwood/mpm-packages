local this

this = {
    options = {
        enabled = false,
        state = {
            block = "rechiseled:obsidian_dark_connecting",
            invisible = false,
            playerPassable = true,
            skyLightPassable = true,
            lightPassable = true
        }
    },
    save = function()
        local file = fs.open("forcefield.json", "w")
        if file then
            file.write(textutils.serializeJSON(this.options))
            file.close()
        else
            print('[!] Could not save forcefield.json')
        end
    end,
    load = function()
        if not fs.exists("forcefield.json") then
            print("No forcefield configuration found, using default values.")
            return this
        end
        local file = fs.open("forcefield.json", "r")
        if not file then
            print('[!] Could not read forcefield.json')
            return this
        end
        local options = textutils.unserializeJSON(file.readAll())
        file.close()
        this.options = options
        return this
    end
}

return this
