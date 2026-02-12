-- StorageType.lua
-- Typed constants for AE2 storage operations
-- Prevents string typos and provides validation

local StorageType = {
    ITEMS = "items",
    FLUIDS = "fluids",
    CHEMICALS = "chemicals"
}

-- Reverse lookup for validation
local validTypes = {}
for name, value in pairs(StorageType) do
    validTypes[value] = name
end

-- Validate a storage type
function StorageType.isValid(storageType)
    return validTypes[storageType] ~= nil
end

-- Get display name for storage type
function StorageType.getDisplayName(storageType)
    if storageType == StorageType.ITEMS then
        return "Items"
    elseif storageType == StorageType.FLUIDS then
        return "Fluids"
    elseif storageType == StorageType.CHEMICALS then
        return "Chemicals"
    else
        return "Unknown"
    end
end

-- Get all valid storage types
function StorageType.all()
    return { StorageType.ITEMS, StorageType.FLUIDS, StorageType.CHEMICALS }
end

return StorageType
