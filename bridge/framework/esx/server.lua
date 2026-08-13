ps.Shared = ps.Shared or {}

local jobs, vehicles = {}, {}

local legacyJobTypes = {
    police = 'leo',
    ambulance = 'ems',
    mechanic = 'mechanic',
}

local function normalizeJob(job)
    if not job then return nil end

    local gradeLevel = tonumber(job.grade) or tonumber(job.grade_level) or 0
    local gradeName = job.grade_name or (type(job.grade) == 'table' and job.grade.name) or tostring(gradeLevel)
    local gradeLabel = job.grade_label or gradeName
    local duty = job.onDuty
    if duty == nil then duty = job.onduty end
    if duty == nil then duty = true end

    return {
        id = job.id,
        name = job.name,
        label = job.label or job.name,
        type = job.type or (jobs[job.name] and jobs[job.name].type) or 'civ',
        onDuty = duty == true,
        onduty = duty == true,
        payment = tonumber(job.grade_salary) or 0,
        isboss = gradeName == 'boss',
        grade = {
            level = gradeLevel,
            name = gradeName,
            label = gradeLabel,
            payment = tonumber(job.grade_salary) or 0,
        },
        grade_level = gradeLevel,
        grade_name = gradeName,
        grade_label = gradeLabel,
        grade_salary = tonumber(job.grade_salary) or 0,
    }
end

local function normalizeOnlinePlayer(xPlayer)
    if not xPlayer then return nil end

    local metadata = xPlayer.getMeta and xPlayer.getMeta() or xPlayer.metadata or {}
    local charinfo = {
        firstname = xPlayer.firstName or '',
        lastname = xPlayer.lastName or '',
        birthdate = xPlayer.dateofbirth,
        gender = xPlayer.sex,
        phone = xPlayer.phoneNumber,
    }

    xPlayer.PlayerData = {
        source = xPlayer.source,
        citizenid = xPlayer.identifier,
        identifier = xPlayer.identifier,
        name = xPlayer.name,
        charinfo = charinfo,
        metadata = metadata or {},
        job = normalizeJob(xPlayer.job),
        money = xPlayer.getAccounts and xPlayer.getAccounts(true) or {},
        items = xPlayer.getInventory and xPlayer.getInventory() or {},
    }

    return xPlayer
end

local function normalizeOfflinePlayer(row)
    if not row then return nil end

    local metadata = {}
    if row.metadata and row.metadata ~= '' then
        metadata = json.decode(row.metadata) or {}
    end

    local job = jobs[row.job] or {}
    local grade = job.grades and job.grades[tostring(row.job_grade)] or {}
    local name = ((row.firstname or '') .. ' ' .. (row.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')

    return {
        source = nil,
        identifier = row.identifier,
        name = name ~= '' and name or row.identifier,
        firstName = row.firstname,
        lastName = row.lastname,
        dateofbirth = row.dateofbirth,
        sex = row.sex,
        job = {
            name = row.job,
            label = job.label or row.job,
            type = job.type or 'civ',
            grade = tonumber(row.job_grade) or 0,
            grade_name = grade.name or tostring(row.job_grade or 0),
            grade_label = grade.label or grade.name or tostring(row.job_grade or 0),
            grade_salary = grade.payment or 0,
            onDuty = metadata.jobDuty ~= false,
        },
        metadata = metadata,
        PlayerData = {
            source = nil,
            citizenid = row.identifier,
            identifier = row.identifier,
            name = name,
            charinfo = {
                firstname = row.firstname or '',
                lastname = row.lastname or '',
                birthdate = row.dateofbirth,
                gender = row.sex,
                phone = row.phone_number,
            },
            metadata = metadata,
            job = normalizeJob({
                name = row.job,
                label = job.label or row.job,
                type = job.type or 'civ',
                grade = tonumber(row.job_grade) or 0,
                grade_name = grade.name or tostring(row.job_grade or 0),
                grade_label = grade.label or grade.name or tostring(row.job_grade or 0),
                grade_salary = grade.payment or 0,
                onDuty = metadata.jobDuty ~= false,
            }),
        },
    }
end

local function loadSharedData()
    local hasType = (MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'jobs' AND column_name = 'type'
    ]]) or 0) > 0
    local jobRows = MySQL.query.await(
        hasType and 'SELECT name, label, type FROM jobs' or 'SELECT name, label FROM jobs',
        {}
    ) or {}
    local gradeRows = MySQL.query.await('SELECT job_name, grade, name, label, salary FROM job_grades', {}) or {}

    for _, row in ipairs(jobRows) do
        jobs[row.name] = {
            name = row.name,
            label = row.label or row.name,
            defaultDuty = true,
            type = row.type or legacyJobTypes[row.name] or 'civ',
            offDutyPay = 0,
            grades = {},
        }
    end

    for _, row in ipairs(gradeRows) do
        local job = jobs[row.job_name]
        if job then
            local grade = {
                name = row.name or row.label,
                label = row.label or row.name,
                level = tonumber(row.grade) or 0,
                payment = tonumber(row.salary) or 0,
                isboss = row.name == 'boss',
            }
            job.grades[tostring(row.grade)] = grade
        end
    end

    local vehicleRows = MySQL.query.await('SELECT model, name, price, category FROM vehicles', {}) or {}
    for _, row in ipairs(vehicleRows) do
        vehicles[string.lower(tostring(row.model))] = {
            name = row.name,
            label = row.name,
            model = row.model,
            price = row.price,
            category = row.category,
        }
    end
end

loadSharedData()
ps.Shared.Vehicles = vehicles
ps.Shared.Jobs = jobs

ps.registerCallback('ps_lib:esx:getVehicleLabel', function(_, model)
    local row = MySQL.single.await('SELECT name FROM vehicles WHERE LOWER(model) = LOWER(?) LIMIT 1', { tostring(model) })
    return row and row.name or tostring(model)
end)

function ps.getPlayer(source)
    return normalizeOnlinePlayer(ESX.GetPlayerFromId(tonumber(source)))
end

function ps.getPlayerByIdentifier(identifier)
    return normalizeOnlinePlayer(ESX.GetPlayerFromIdentifier(identifier))
end

function ps.getOfflinePlayer(identifier)
    local online = ps.getPlayerByIdentifier(identifier)
    if online then return online end

    local row = MySQL.single.await([[
        SELECT identifier, firstname, lastname, dateofbirth, sex, phone_number,
               job, job_grade, metadata
        FROM users WHERE identifier = ? LIMIT 1
    ]], { identifier })
    return normalizeOfflinePlayer(row)
end

function ps.getIdentifier(source)
    local player = ps.getPlayer(source)
    return player and player.identifier or nil
end

function ps.getSource(identifier)
    local player = ps.getPlayerByIdentifier(identifier)
    return player and player.source or nil
end

function ps.getPlayerName(source)
    local player = ps.getPlayer(source)
    return player and player.name or nil
end

function ps.getPlayerNameByIdentifier(identifier)
    local player = ps.getPlayerByIdentifier(identifier) or ps.getOfflinePlayer(identifier)
    return player and player.name or 'Unknown Person'
end

function ps.getPlayerData(source)
    local player = ps.getPlayer(source)
    return player and player.PlayerData or nil
end

function ps.getMetadata(source, meta)
    local player = ps.getPlayer(source)
    if not player then return nil end
    if meta == 'isdead' then
        return player.getMeta and player.getMeta('dead') or false
    end
    return player.getMeta and player.getMeta(meta) or (player.metadata and player.metadata[meta])
end

function ps.setMetadata(sourceOrIdentifier, meta, value)
    local player = type(sourceOrIdentifier) == 'number'
        and ps.getPlayer(sourceOrIdentifier)
        or ps.getPlayerByIdentifier(sourceOrIdentifier)

    if player and player.setMeta then
        player.setMeta(meta, value)
        normalizeOnlinePlayer(player)
        return true
    end

    if type(sourceOrIdentifier) ~= 'string' then return false end
    local row = MySQL.single.await('SELECT metadata FROM users WHERE identifier = ? LIMIT 1', { sourceOrIdentifier })
    if not row then return false end
    local metadata = row.metadata and json.decode(row.metadata) or {}
    metadata[meta] = value
    return (MySQL.update.await('UPDATE users SET metadata = ? WHERE identifier = ?', {
        json.encode(metadata), sourceOrIdentifier
    }) or 0) > 0
end

function ps.getCharInfo(source, info)
    local data = ps.getPlayerData(source)
    return data and data.charinfo and data.charinfo[info] or nil
end

function ps.getJob(source)
    local data = ps.getPlayerData(source)
    return data and data.job or nil
end

function ps.getJobName(source)
    local job = ps.getJob(source)
    return job and job.name or nil
end

function ps.getJobType(source)
    local job = ps.getJob(source)
    return job and job.type or 'civ'
end

function ps.getJobDuty(source)
    local job = ps.getJob(source)
    return job and job.onduty == true or false
end

function ps.getJobData(source, data)
    local job = ps.getJob(source)
    if not data then return job end
    return job and job[data] or nil
end

function ps.getJobGrade(source)
    local job = ps.getJob(source)
    return job and job.grade or nil
end

function ps.getJobGradeLevel(source)
    local grade = ps.getJobGrade(source)
    return grade and grade.level or nil
end

function ps.getJobGradeName(source)
    local grade = ps.getJobGrade(source)
    return grade and grade.name or nil
end

function ps.getJobGradePay(source)
    local grade = ps.getJobGrade(source)
    return grade and grade.payment or 0
end

function ps.isBoss(source)
    local job = ps.getJob(source)
    return job and job.isboss == true or false
end

function ps.getAllPlayers()
    if ESX.GetExtendedPlayers then
        return ESX.GetExtendedPlayers(nil, nil, true)
    end
    return ESX.GetPlayers()
end

function ps.getEntityCoords(source)
    return GetEntityCoords(GetPlayerPed(source))
end

function ps.getDistance(source, location)
    local pcoords = GetEntityCoords(GetPlayerPed(source))
    return #(pcoords - vector3(location.x, location.y, location.z))
end

function ps.checkDistance(source, location, distance)
    return ps.getDistance(source, location) <= (distance or 2.5)
end

function ps.getNearbyPlayers(source, distance)
    local players = {}
    for _, playerSource in pairs(ps.getAllPlayers() or {}) do
        playerSource = tonumber(playerSource)
        if playerSource and playerSource ~= tonumber(source) then
            local dist = #(GetEntityCoords(GetPlayerPed(playerSource)) - GetEntityCoords(GetPlayerPed(source)))
            if dist < (distance or 10.0) then
                players[#players + 1] = {
                    value = ps.getIdentifier(playerSource),
                    label = ps.getPlayerName(playerSource),
                    source = playerSource,
                    distance = dist,
                }
            end
        end
    end
    return players
end

function ps.getJobCount(jobName)
    local count = 0
    for _, playerSource in pairs(ps.getAllPlayers() or {}) do
        if ps.getJobName(playerSource) == jobName and ps.getJobDuty(playerSource) then
            count = count + 1
        end
    end
    return count
end

function ps.getJobTypeCount(jobType)
    local count = 0
    for _, playerSource in pairs(ps.getAllPlayers() or {}) do
        if ps.getJobType(playerSource) == jobType and ps.getJobDuty(playerSource) then
            count = count + 1
        end
    end
    return count
end

function ps.createUseable(item, func)
    if not item or not func then return end
    ESX.RegisterUsableItem(item, func)
end

function ps.setJob(source, jobName, rank)
    local player = ps.getPlayer(source)
    rank = tonumber(rank) or 0
    if not player or not ESX.DoesJobExist(jobName, rank) then return false end
    player.setJob(jobName, rank)
    return true
end

function ps.setJobDuty(source, duty)
    local player = ps.getPlayer(source)
    if not player then return false end
    player.setJob(player.job.name, player.job.grade, duty == true)
    return true
end

function ps.addMoney(source, accountType, amount, reason)
    local player = ps.getPlayer(source)
    if not player then return false end
    if accountType == nil or accountType == 'cash' then
        player.addMoney(amount, reason or 'Added by script')
        return true
    end
    if accountType == 'bank' then
        player.addAccountMoney('bank', amount, reason or 'Added by script')
        return true
    end
    return false
end

function ps.removeMoney(source, accountType, amount, reason)
    local player = ps.getPlayer(source)
    if not player then return false end
    accountType = accountType or 'cash'
    local account = accountType == 'cash' and player.getAccount('money') or player.getAccount(accountType)
    if not account or account.money < amount then return false end
    player.removeAccountMoney(account.name, amount, reason or 'Removed by script')
    return true
end

function ps.getMoney(source, accountType)
    local player = ps.getPlayer(source)
    if not player then return 0 end
    accountType = accountType or 'cash'
    local account = player.getAccount(accountType == 'cash' and 'money' or accountType)
    return account and account.money or 0
end

function ps.getAllJobs()
    local names = {}
    for name in pairs(jobs) do names[#names + 1] = name end
    return names
end

function ps.getJobTable()
    return jobs
end

function ps.getSharedJob(jobName)
    return jobName and jobs[jobName] or nil
end

function ps.getSharedJobData(jobName, data)
    local job = ps.getSharedJob(jobName)
    if not data then return job end
    return job and job[data] or nil
end

function ps.getSharedJobGrade(jobName, grade)
    local job = ps.getSharedJob(jobName)
    return job and job.grades[tostring(grade)] or nil
end

function ps.getSharedVehicle(model)
    if not model then return nil end
    return vehicles[string.lower(tostring(model))]
end

function ps.getSharedVehicleData(model, data)
    local vehicle = ps.getSharedVehicle(model)
    if not data then return vehicle end
    return vehicle and vehicle[data] or nil
end

function ps.getGang() return nil end
function ps.getGangName() return nil end
function ps.getGangData() return nil end
function ps.getGangGrade() return nil end
function ps.getGangGradeLevel() return nil end
function ps.getGangGradeName() return nil end
function ps.isLeader() return false end
function ps.getAllGangs() return {} end

function ps.vehicleOwner(licensePlate)
    return MySQL.scalar.await('SELECT owner FROM owned_vehicles WHERE plate = ? LIMIT 1', { licensePlate }) or false
end

function ps.jobExists(jobName)
    return jobs[jobName] ~= nil
end

function ps.hasPermission(source, permission)
    return IsPlayerAceAllowed(source, permission) == true
end

function ps.getSharedItems()
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:GetItems()
    end
    return ESX.GetItems and ESX.GetItems() or ESX.Items or {}
end

function ps.getItemLabel(item)
    local itemData = ps.getSharedItems()[item]
    return itemData and itemData.label or item
end

function ps.getItemWeight(item)
    local itemData = ps.getSharedItems()[item]
    return itemData and itemData.weight or 0
end

RegisterNetEvent('ps_lib:server:toggleDuty', function(duty)
    local playerSource = source

    -- Callers such as ps-mdt send no value because this is a toggle action.
    -- Preserve explicit true/false requests, otherwise invert current duty.
    if type(duty) ~= 'boolean' then
        duty = not ps.getJobDuty(playerSource)
    end

    ps.setJobDuty(playerSource, duty)
end)
