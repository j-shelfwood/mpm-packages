local this

this = {
    forger = {},
    find = function(forger)
        this.forger = forger
        -- Check if the `anchors.json` file exists
        if not fs.exists("anchors.json") then
            print('No `anchors.json` file found, detecting anchors...')
            return this.detect()
        else
            print('Loading anchors from `anchors.json`...')
            return this.load()
        end
    end,
    detect = function()
        print('Detecting anchors...')
        -- Start tracking time 
        local startTime = os.clock()
        local anchors = this.forger.detectAnchors()
        -- Stop tracking time
        local endTime = os.clock()
        print(#anchors .. 'anchors detected in ' .. endTime - startTime .. ' seconds!')

        -- Save the anchors to the `anchors.json` file
        local file = fs.open("anchors.json", "w")
        if file then
            file.write(textutils.serializeJSON(anchors))
            file.close()
            print('Anchors saved to `anchors.json`!')
        else
            print('[!] Could not save anchors.json')
        end
        return anchors
    end,
    load = function()
        print('Loading anchors...')
        local file = fs.open("anchors.json", "r")
        if not file then
            print('[!] Could not read anchors.json')
            return {}
        end
        local anchors = textutils.unserializeJSON(file.readAll())
        file.close()
        return anchors
    end
}

return this
