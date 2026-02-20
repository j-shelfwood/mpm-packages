local PairingSession = {}

local function copyEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local out = {}
    for k, v in pairs(entry) do
        out[k] = v
    end
    return out
end

function PairingSession.reserve(authority, computerId, computerLabel)
    if not authority.initialized then
        return nil, "Swarm not initialized"
    end
    if not computerId then
        return nil, "Missing computer ID"
    end

    local existing = authority.registry:get(computerId)
    local previous = copyEntry(existing)
    local computerSecret = existing and existing.secret or nil
    if not computerSecret or (existing and existing.status ~= "active") then
        computerSecret = authority.registry:generateSecret()
    end

    local creds = {
        computerId = computerId,
        computerSecret = computerSecret,
        swarmId = authority.identity.id,
        swarmSecret = authority.identity.secret,
        swarmFingerprint = authority.identity.fingerprint
    }

    authority.pendingPairings[computerId] = {
        computerId = computerId,
        computerLabel = computerLabel,
        previous = previous,
        creds = creds
    }

    return creds
end

function PairingSession.commit(authority, computerId, computerLabel)
    if not authority.initialized then
        return nil, "Swarm not initialized"
    end

    local pending = authority.pendingPairings[computerId]
    if not pending then
        return nil, "No pending pairing"
    end

    local entry, err = authority.registry:upsert(
        computerId,
        computerLabel or pending.computerLabel,
        pending.creds.computerSecret
    )
    if not entry then
        return nil, err
    end

    authority.pendingPairings[computerId] = nil
    authority:save()

    return {
        computerId = computerId,
        computerSecret = entry.secret,
        swarmId = authority.identity.id,
        swarmSecret = authority.identity.secret,
        swarmFingerprint = authority.identity.fingerprint
    }
end

function PairingSession.cancel(authority, computerId)
    local pending = authority.pendingPairings[computerId]
    if not pending then
        return true
    end

    if pending.previous then
        authority.registry:set(computerId, pending.previous)
    else
        authority.registry:remove(computerId)
    end

    authority.pendingPairings[computerId] = nil
    authority:save()
    return true
end

function PairingSession.issue(authority, computerId, computerLabel)
    local creds, err = PairingSession.reserve(authority, computerId, computerLabel)
    if not creds then
        return nil, err
    end

    local committed, commitErr = PairingSession.commit(authority, computerId, computerLabel)
    if not committed then
        return nil, commitErr
    end

    return committed
end

return PairingSession
