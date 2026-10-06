local packets = require('packets')
require('strings')

_addon.name = 'SendAllTarget'
_addon.version = '1.3-reports'
_addon.author = 'Selindrile, Thanks and apologies to Arcon for abusing his code.'
_addon.commands = {'sendalltarget','sendallt','sendat','sat'}


-- v1.3: requires Send and this version of SendAllTarget on every instance.
-- fetch NAME / fetchtarget NAME: copy one character's target.
-- fetchall: report other characters' targets without changing your target.
-- alltargetreport / alltarget report: broadcast, verify, report to sender.
-- Replies are correlated and deduplicated; report commands never retarget sender.
local pending, serial = {}, 0

local function say(text)
    windower.add_to_chat(207, '[SAT] ' .. text)
end

local function valid_name(name)
    return type(name) == 'string' and name:match('^[A-Za-z]+$') ~= nil
end

-- Names travel as hex so spaces, quotes and command separators stay literal.
local function encode(text)
    return (text:gsub('.', function(c) return string.format('%02X', c:byte()) end))
end

local function decode(text)
    if not text or #text % 2 ~= 0 or text:find('[^%x]') then return nil end
    return (text:gsub('%x%x', function(c) return string.char(tonumber(c, 16)) end))
end

local function send_to(who, text)
    windower.send_command('send ' .. who .. ' sendalltarget ' .. text)
end

local function select_target(id, zone)
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in then return 'not_logged_in' end
    if info.zone ~= zone then return 'different_zone' end
    local target = windower.ffxi.get_mob_by_id(id)
    if not target then return 'not_visible' end
    local player = windower.ffxi.get_mob_by_target('me')
    if not player then return 'no_player' end
    local ok = pcall(function()
        packets.inject(packets.new('incoming', 0x058, {
            ['Player'] = player.id,
            ['Target'] = target.id,
            ['Player Index'] = player.index,
        }))
    end)
    if not ok then return 'packet_error' end
    coroutine.sleep(1)
    info = windower.ffxi.get_info()
    if not info or not info.logged_in or info.zone ~= zone then return 'zone_changed' end
    local selected = windower.ffxi.get_mob_by_target('t')
    return selected and selected.id == id and 'match' or 'mismatch'
end

local reasons = {
    match = 'MATCH', mismatch = 'FAILED: target did not stick',
    not_visible = 'FAILED: requested ID is not visible on this client',
    different_zone = 'FAILED: different zone', zone_changed = 'FAILED: zone changed',
    not_logged_in = 'FAILED: not logged in', no_player = 'FAILED: player unavailable',
    packet_error = 'FAILED: target-change packet error',
}

local function start_request(mode, who)
    local info = windower.ffxi.get_info()
    local player = windower.ffxi.get_player()
    if not info or not info.logged_in or not player then say('Not logged in.'); return end
    if mode == 'fetch' and not valid_name(who) then
        say('Usage: //sat fetch <character>'); return
    end
    local target = windower.ffxi.get_mob_by_target('t')
    if mode == 'target' and not target then say('Select a target first.'); return end
    serial = serial + 1
    local token = tostring(os.time()) .. '-' .. tostring(serial)
    local request = {mode=mode, who=who, zone=info.zone, player=player.name,
        seen={}, count=0, matched=0, id=mode == 'target' and target.id or 0}
    pending[token] = request
    if mode == 'target' then
        say('Asking others to target ' .. target.name .. ' (' .. target.id .. ')...')
    elseif mode == 'fetch' then
        say('Requesting ' .. who .. "'s current target...")
    else
        say("Requesting other characters' targets...")
    end
    send_to(who or '@others', table.concat({'_satrequest', token, player.name,
        mode, tostring(info.zone), tostring(request.id)}, ' '))
    coroutine.sleep(5)
    pending[token] = nil
    if request.count == 0 then
        say('No replies within 5 seconds. Check Send and SAT v1.3 on the other instances.')
    elseif mode ~= 'fetch' then
        local summary = tostring(request.count) .. ' character(s) replied'
        if mode == 'target' then summary = summary .. '; ' .. request.matched .. ' matched' end
        say(summary .. '. Only responding instances are counted.')
    end
end

local function respond(token, requester, mode, zone, id)
    if not token or not token:match('^%d+%-%d+$') or not valid_name(requester) then return end
    if mode ~= 'fetch' and mode ~= 'peek' and mode ~= 'target' then return end
    zone, id = tonumber(zone), tonumber(id)
    if not zone or not id or (mode == 'target' and id <= 0) then return end
    local player = windower.ffxi.get_player()
    if not player then return end
    local status = mode == 'target' and select_target(id, zone) or 'observed'
    local info = windower.ffxi.get_info()
    local current_player = windower.ffxi.get_player()
    if not current_player or current_player.name ~= player.name then return end
    local selected = info and info.logged_in and windower.ffxi.get_mob_by_target('t')
    send_to(requester, table.concat({'_satresult', token, player.name,
        tostring(info and info.zone or 0), tostring(selected and selected.id or 0),
        status, selected and encode(selected.name) or '00'}, ' '))
end

local function receive(token, name, zone, id, status, encoded_name)
    local request = pending[token]
    if not request or not valid_name(name) or request.seen[name:lower()] then return end
    if request.who and request.who:lower() ~= name:lower() then return end
    zone, id = tonumber(zone), tonumber(id)
    if not zone or not id or id < 0 or (status ~= 'observed' and not reasons[status]) then return end
    local target_name = id > 0 and decode(encoded_name) or 'nothing'
    if not target_name then return end
    request.seen[name:lower()] = true
    request.count = request.count + 1
    local info = windower.ffxi.get_info()
    local player = windower.ffxi.get_player()
    if not player or player.name ~= request.player or not info or not info.logged_in then return end
    local label = id > 0 and (target_name .. ' (' .. id .. ')') or 'nothing'
    if zone ~= info.zone then label = label .. ' [zone ' .. zone .. ']' end
    if request.mode == 'target' then
        local matched = status == 'match' and id == request.id and zone == request.zone
        if matched then request.matched = request.matched + 1 end
        say(name .. ' -> ' .. label .. ' | ' ..
            (matched and 'MATCH' or (reasons[status] ~= 'MATCH' and reasons[status] or nil) or 'FAILED: different target'))
    else
        say(name .. ' -> ' .. label)
        if request.mode == 'fetch' then
            if id == 0 then say(name .. ' has no current target.'); return end
            if info.zone ~= request.zone then say('Your zone changed; fetch cancelled.'); return end
            local result = select_target(id, zone)
            if result ~= 'match' then say(reasons[result]) end
        end
    end
end

local function new_command(cmd, cmd2, ...)
    if cmd == 'fetch' or cmd == 'fetchtarget' then start_request('fetch', cmd2)
    elseif cmd == 'fetchall' then start_request('peek')
    elseif cmd == 'alltargetreport' or (cmd == 'alltarget' and cmd2 == 'report') then
        start_request('target')
    elseif cmd == '_satrequest' then respond(cmd2, ...)
    elseif cmd == '_satresult' then receive(cmd2, ...)
    elseif cmd == 'help' then
        say('fetch <name>: copy target | fetchall: report others | alltargetreport (or alltarget report): send + verify')
        say('alltarget: original broadcast | target <id>: verbose diagnostic')
    else return false end
    return true
end

windower.register_event('addon command',function (cmd,cmd2,...)
    cmd = cmd and cmd:lower()
    if new_command(cmd, cmd2, ...) then return end
    if cmd == 'alltarget' or cmd == 'youtarget' or cmd == 'allattack'
        or cmd == 'youattack' or cmd == 'allswitch' or cmd == 'youswitch' then
        if not windower.ffxi.get_mob_by_target('t') then say('Select a target first.'); return end
        if cmd:sub(1, 3) == 'you' and not valid_name(cmd2) then
            say('Provide a character name.'); return
        end
    end
	if cmd == nil then return
	elseif cmd == 'stop' or cmd == 'unfollow' then
		windower.ffxi.run(false)
		windower.ffxi.follow()
	elseif cmd == 'alltarget' then
		local target = windower.ffxi.get_mob_by_target('t')
		windower.send_command('send @all sendalltarget target ' .. tostring(target.id))
	elseif cmd == 'youtarget' then
		local target = windower.ffxi.get_mob_by_target('t')
		windower.send_command('send '..cmd2..' sendalltarget target ' .. tostring(target.id))
	elseif cmd == 'allattack' then
		local target = windower.ffxi.get_mob_by_target('t')
		windower.send_command('send @all sendalltarget attack ' .. tostring(target.id))
	elseif cmd == 'youattack' then
		local target = windower.ffxi.get_mob_by_target('t')
		windower.send_command('send '..cmd2..' sendalltarget attack ' .. tostring(target.id))
	elseif cmd == 'allswitch' then
		local target = windower.ffxi.get_mob_by_target('t')
		windower.send_command('send @all sendalltarget switch ' .. tostring(target.id))
	elseif cmd == 'youswitch' then
		local target = windower.ffxi.get_mob_by_target('t')
		windower.send_command('send '..cmd2..' sendalltarget switch ' .. tostring(target.id))
	elseif cmd == 'attack' or cmd == 'switch' then
		local id = tonumber(cmd2)
		local target = windower.ffxi.get_mob_by_id(id)
		local category
		if cmd == 'attack' then
			category = 0x02
		elseif cmd == 'switch' then
			category = 0x0F
		else
			return
		end
		if target and target.valid_target and target.spawn_type == 16 and math.sqrt(target.distance) <= 30 then
			packets.inject(packets.new('outgoing', 0x1a, {
				['Target'] = target.id,
				['Target Index'] = target.index,
				['Category']     = category,
			}))
		end
	elseif cmd == 'target' then
        local function report(text)
            windower.add_to_chat(207, '[SAT diagnostic] ' .. text)
        end
        local id = tonumber(cmd2)
        if not id then
            report('Usage: //sat target <numeric ID>')
            return
        end
        local info = windower.ffxi.get_info()
        if not info.logged_in then
            report('Not logged in.')
            return
        end
        local target = windower.ffxi.get_mob_by_id(id)
        if not target then
            report('NPC ID ' .. id .. ' not found on this client. Zone: ' .. tostring(info.zone))
            return
        end
        local player = windower.ffxi.get_mob_by_target('me')
        if not player then
            report("Could not read this character's entity.")
            return
        end
        report('Found ' .. target.name .. ' | ID ' .. target.id .. ' | index ' .. target.index
            .. ' | valid ' .. tostring(target.valid_target)
            .. ' | distance ' .. string.format('%.1f', math.sqrt(target.distance or 0)))
        local ok, err = pcall(function()
            packets.inject(packets.new('incoming', 0x058, {
                ['Player'] = player.id,
                ['Target'] = target.id,
                ['Player Index'] = player.index,
            }))
        end)
        if not ok then
            report('Target-change error: ' .. tostring(err))
            return
        end
        coroutine.sleep(1)
        local selected = windower.ffxi.get_mob_by_target('t')
        if selected and selected.id == id then
            report('SUCCESS: selected ' .. selected.name)
        else
            report('Target change did not take. Selected: ' .. (selected and
                (selected.name .. ' (' .. selected.id .. ')') or 'nothing'))
        end
	elseif cmd == 'allcommand' then
		local command = ...
		local mobid = windower.ffxi.get_mob_by_target('t')
		if mobid and mobid.id then
			if command == nil then
				windower.send_command('send @all '..cmd2..' '..mobid.id..'')
			elseif cmd2 then
				windower.send_command('send @all '..cmd2..' '..command..' '..mobid.id..'')
			end
		end
	elseif cmd == 'youcommand' then
		local command = ...
		local mobid = windower.ffxi.get_mob_by_target('t')
		if mobid and mobid.id then
			windower.send_command('send '..cmd2..' '..command..' '..mobid.id..'')
		end
    end
end)