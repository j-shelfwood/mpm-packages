local KeyPair = mpm('crypto/KeyPair')

local SwarmIdentity = {}

function SwarmIdentity.exists(identityPath)
    return fs.exists(identityPath)
end

function SwarmIdentity.create(registry, swarmName)
    local swarmId = "swarm_" .. os.getComputerID() .. "_" .. os.epoch("utc")
    local secret = registry:generateSecret()
    local fingerprint = KeyPair.fingerprint(secret)

    return {
        id = swarmId,
        name = swarmName or ("Swarm " .. os.getComputerID()),
        secret = secret,
        fingerprint = fingerprint,
        createdAt = os.epoch("utc"),
        pocketId = os.getComputerID()
    }
end

function SwarmIdentity.load(identityPath)
    if not fs.exists(identityPath) then
        return nil
    end

    local file = fs.open(identityPath, "r")
    if not file then
        return nil
    end

    local content = file.readAll()
    file.close()

    local ok, identity = pcall(textutils.unserialize, content)
    if not ok or not identity then
        return nil
    end

    return identity
end

function SwarmIdentity.save(identityPath, identity)
    local file = fs.open(identityPath, "w")
    if not file then
        return false
    end
    file.write(textutils.serialize(identity))
    file.close()
    return true
end

function SwarmIdentity.delete(identityPath)
    if fs.exists(identityPath) then
        fs.delete(identityPath)
    end
end

function SwarmIdentity.getInfo(identity, registry)
    if not identity then
        return nil
    end

    return {
        id = identity.id,
        name = identity.name,
        fingerprint = identity.fingerprint,
        pocketId = identity.pocketId,
        computerCount = registry:countActive()
    }
end

return SwarmIdentity
