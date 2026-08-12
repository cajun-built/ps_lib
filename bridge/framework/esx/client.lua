local esxMetadata = {
    health = 0,
    armor = 0,
    thirst = 0,
    hunger = 0,
    stress = 0,
}

local function normalizeJob(job)
    if not job then return nil end
    local duty = job.onDuty
    if duty == nil then duty = job.onduty end
    if duty == nil then duty = true end
    local level = tonumber(job.grade) or tonumber(job.grade_level) or 0
    local name = job.grade_name or tostring(level)

    return {
        id = job.id,
        name = job.name,
        label = job.label or job.name,
        type = job.type or 'civ',
        onDuty = duty == true,
        onduty = duty == true,
        isboss = name == 'boss',
        payment = tonumber(job.grade_salary) or 0,
        grade = {
            level = level,
            name = name,
            label = job.grade_label or name,
            payment = tonumber(job.grade_salary) or 0,
        },
        grade_level = level,
        grade_name = name,
        grade_label = job.grade_label or name,
        grade_salary = tonumber(job.grade_salary) or 0,
    }
end

local function normalizedPlayerData()
    local data = ESX.GetPlayerData() or {}
    local metadata = data.metadata or {}
    local charinfo = {
        firstname = data.firstName or '',
        lastname = data.lastName or '',
        birthdate = data.dateofbirth,
        age = data.dateofbirth,
        gender = data.sex,
        phone = data.phoneNumber,
    }

    return {
        source = GetPlayerServerId(PlayerId()),
        citizenid = data.identifier,
        identifier = data.identifier,
        name = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''),
        charinfo = charinfo,
        metadata = metadata,
        job = normalizeJob(data.job),
        money = data.accounts or {},
        raw = data,
    }
end

local function refreshLocalData(playerData)
    playerData = playerData or ESX.GetPlayerData() or {}
    ps.ped = PlayerPedId()
    ps.charinfo = {
        firstname = playerData.firstName or '',
        lastname = playerData.lastName or '',
        birthdate = playerData.dateofbirth,
        age = playerData.dateofbirth,
        gender = playerData.sex,
    }
    ps.name = ((ps.charinfo.firstname or '') .. ' ' .. (ps.charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    ps.identifier = playerData.identifier
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ps.ped = nil
    ps.charinfo = nil
    ps.name = nil
    ps.identifier = nil
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        refreshLocalData()
    end
end)

RegisterNetEvent('esx:playerLoaded', function(playerData)
    refreshLocalData(playerData)
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    ps.charinfo = nil
    ps.name = nil
    ps.identifier = nil
end)

AddEventHandler('esx_status:onTick', function(data)
    for i = 1, #(data or {}) do
        if esxMetadata[data[i].name] ~= nil then
            esxMetadata[data[i].name] = math.floor(data[i].percent or 0)
        end
    end
    local ped = PlayerPedId()
    esxMetadata.health = math.max(0, GetEntityHealth(ped) - 100)
    esxMetadata.armor = GetPedArmour(ped)
end)

RegisterNetEvent('esx:setJob', function(job)
    ESX.PlayerData.job = job
end)

function ps.getPlayerData()
    return normalizedPlayerData()
end

function ps.getIdentifier()
    return ps.getPlayerData().identifier
end
ps.getCid = ps.getIdentifier

function ps.getMetadata(meta)
    if esxMetadata[meta] ~= nil then return esxMetadata[meta] end
    if meta == 'isdead' then return ps.isDead() end
    return ps.getPlayerData().metadata[meta]
end

function ps.getCharInfo(info)
    return ps.getPlayerData().charinfo[info]
end

function ps.getPlayerName()
    return ps.getPlayerData().name
end
ps.getName = ps.getPlayerName

function ps.getPlayer()
    return PlayerPedId()
end

function ps.getVehicleLabel(model)
    local lookup = model
    if type(model) == 'number' and DoesEntityExist(model) then
        lookup = GetEntityModel(model)
    end
    local display = type(lookup) == 'number' and GetDisplayNameFromVehicleModel(lookup) or tostring(lookup)
    return ps.callback('ps_lib:esx:getVehicleLabel', display) or display
end

function ps.isDead()
    local data = ESX.GetPlayerData() or {}
    local metadata = data.metadata or {}
    if data.dead == true or metadata.dead == true or metadata.isdead == true then return true end
    local ped = PlayerPedId()
    return IsEntityDead(ped) or IsPedFatallyInjured(ped)
end

function ps.getJob()
    return ps.getPlayerData().job
end

function ps.getJobName()
    local job = ps.getJob()
    return job and job.name or nil
end

function ps.getJobDuty()
    local job = ps.getJob()
    return job and job.onduty == true or false
end

function ps.getJobLabel()
    local job = ps.getJob()
    return job and job.label or nil
end

function ps.getJobType()
    local job = ps.getJob()
    return job and job.type or 'civ'
end

function ps.isBoss()
    local job = ps.getJob()
    return job and job.isboss == true or false
end

function ps.defaultDuty()
    local job = ps.getJob()
    return job and job.onduty == true or false
end

function ps.getJobData(data)
    local job = ps.getJob()
    if not data then return job end
    return job and job[data] or nil
end

function ps.getGang() return nil end
function ps.getGangName() return nil end
function ps.getGangData() return nil end
function ps.isLeader() return false end

function ps.getCoords()
    return GetEntityCoords(PlayerPedId())
end

function ps.getMoneyData()
    local result = { cash = 0, bank = 0 }
    local data = ESX.GetPlayerData() or {}
    for _, account in ipairs(data.accounts or {}) do
        if account.name == 'money' then result.cash = account.money or 0 end
        if account.name == 'bank' then result.bank = account.money or 0 end
    end
    if data.money then result.cash = data.money end
    return result
end

function ps.getMoney(accountType)
    return ps.getMoneyData()[accountType or 'cash'] or 0
end

function ps.getAllMoney()
    local moneyData = {}
    for name, amount in pairs(ps.getMoneyData()) do
        moneyData[#moneyData + 1] = { amount = amount, name = name }
    end
    return moneyData
end

exports('getPlayerData', ps.getPlayerData)
exports('getIdentifier', ps.getIdentifier)
exports('getCid', ps.getCid)
exports('getMetadata', ps.getMetadata)
exports('getCharInfo', ps.getCharInfo)
exports('getPlayerName', ps.getPlayerName)
exports('getName', ps.getName)
exports('getPlayer', ps.getPlayer)
exports('getVehicleLabel', ps.getVehicleLabel)
exports('isDead', ps.isDead)
exports('getJob', ps.getJob)
exports('getJobName', ps.getJobName)
exports('getJobType', ps.getJobType)
exports('isBoss', ps.isBoss)
exports('getJobDuty', ps.getJobDuty)
exports('getJobData', ps.getJobData)
exports('getGang', ps.getGang)
exports('getGangName', ps.getGangName)
exports('defaultDuty', ps.defaultDuty)
exports('isLeader', ps.isLeader)
exports('getGangData', ps.getGangData)
exports('getCoords', ps.getCoords)
exports('getMoneyData', ps.getMoneyData)
exports('getMoney', ps.getMoney)
exports('getAllMoney', ps.getAllMoney)
