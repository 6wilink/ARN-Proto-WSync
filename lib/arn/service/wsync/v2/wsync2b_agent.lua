-- by Qige <qigezhao@gmail.com>
-- 2017.10.20 ARN iOMC v3.0-alpha-201017Q

--local DBG = print
local DBG = function(msg) end

local CCFF      = require 'arn.utils.ccff'
local ARNMngr   = require 'arn.device.mngr'
local TOKEN     = require 'arn.service.wsync.v2.util_token'

local exec  = CCFF.execute
local ssplit = CCFF.split
local fwrite = CCFF.file.write
local fread = CCFF.file.read
local striml = CCFF.triml
local tbl_push = table.insert

local sfmt  = string.format
local schar = string.char
local sbyte = string.byte
local ssub  = string.sub
local ts    = os.time
local dt    = function() return os.date('%X %x') end


local WSync2Agent = {}
WSync2Agent.VERSION = 'ARN-Agent-WSync v2.0-alpha-20171206Q'

WSync2Agent.Comm = require 'arn.service.wsync.v2.util_comm'

WSync2Agent.conf = {}
WSync2Agent.conf.fmtTokenKey = "6W+ARN+%s"

WSync2Agent.instant = {}
WSync2Agent.instant.__index = WSync2Agent.instant -- OOP liked(1/2)

function WSync2Agent.New(
    protocol, port,
    interval, flagLoop
)
    local instant = {}
    setmetatable(instant, WSync2Agent.instant) -- OOP liked(2/2)

    instant.VERSION = WSync2Agent.VERSION
    instant.conf = {}
    instant.conf.protocol = protocol or 'udp'
    instant.conf.port = port or 3003
    instant.conf.interval = interval or 1
    instant.conf.flagLoop = flagLoop

    -- Resource
    instant.res = {}
    instant.res.channels = nil
    instant.res.timeouts = nil
    instant.res.loops = 0

    instant.cache = {}
    instant.cache.index = 1
    instant.cache.target = nil
    instant.cache.timeout = nil

    return (instant)
end

function WSync2Agent.instant:Prepare(timeout, port, protocol)
    DBG(sfmt("Agent.instant:Prepare(%s)", timeout or '-'))

    if ((not ARNMngr)) then
        return 'error: need packet ARN-Scripts'
    end

    if ((not WSync2Agent.Comm) or (not WSync2Agent.Comm.Env())) then
        return 'error: utility wsync2 comm failed'
    end

    -- enable run again & again
    if (self.conf.flagLoop == 'on' and self.conf.flagLoop == '1') then
        self.conf.flagLoop = 1
    else
        self.conf.flagLoop = 0
    end

    -- init socket
    local sockfd = WSync2Agent.Comm.Socket(timeout, port, protocol)
    if (not sockfd) then
        return 'error: bad local socket'
    end
    self.res.sockfd = sockfd

    -- init TOKEN
    local token = self:tokenGenerate()
    if (not token) then
        return 'error: cannot calc local token'
    end

    self.res.TOKEN = token
    self.res.ts = ts()
    return nil
end

function WSync2Agent.instant:AllParamsReset()
    DBG('------# reset loops & index')
    self.res.loops = 0
    self.res.channels = nil
    self.res.timeouts = nil

    self.cache.index = 1
    self.cache.timeout = nil
end


function WSync2Agent.findMaxSize(size1, size2)
    if (size1 and size2) then
        if (size1 > size2) then
            return size1
        end
        return size2
    end
    return 0
end


function WSync2Agent.GetMsgType(config)
    return WSync2Agent.parseConfig(config, 3)
end

function WSync2Agent.GetChannels(config)
    return WSync2Agent.parseConfig(config, 1, 1)
end

function WSync2Agent.GetTimers(config)
    return WSync2Agent.parseConfig(config, 2, 1)
end

function WSync2Agent.parseConfig(config, idx, flagTable)
    local i = idx or 1
    local cfg = ssplit(config, ':')
    if (cfg and i <= #cfg) then
        local vs = cfg[i]
        if (not flagTable) then
            return vs
        end

        if (vs) then
            local vl = ssplit(vs, ',')
            return vl
        end
    end
    return nil
end


function WSync2Agent.sayStatusAppend(path, msg)
    local oldTxt = fread(path) or ''
    local txt = oldTxt .. msg
    WSync2Agent.sayStatus(path, txt)
end

function WSync2Agent.sayStatus(path, msg)
    local txt = sfmt('%s [%s]\n', msg or '-', dt())
    fwrite(path, txt)
end

function WSync2Agent.writeLocalConfig(stdin, msg)
    local lmsgRaw = fread(stdin)
    local lmsg = string.gsub(lmsgRaw, '\n', '')
    local lmtype = WSync2Agent.GetMsgType(lmsg) or ''
    DBG(sfmt('### local config: %s, local mtype: %s', lmsg or '-', lmtype or '-'))
    -- overwrite local config if not user defined
    local flagLocalUserDefined = string.find(lmtype, 'cliset')
    if (msg and lmtype and (not flagLocalUserDefined)) then
        fwrite(stdout, s)
        fwrite(stdin, msg..'\n')
    end
end

function WSync2Agent.freeRunIdle(stdout, status, sockfd, port, msg)
    WSync2Agent.sayStatus(stdout, status)
    WSync2Agent.Comm.TellEveryPeerMsg(sockfd, port, msg)
    print('----'..status)
end

-- check local config type before write
-- must not 'cliset'
function WSync2Agent.instant:TaskLanSync(
    stdin, stdout
)
    local msg, host, port = WSync2Agent.Comm.HearFromAllPeers(self.res.sockfd)
    local s = sfmt('# heard from: %s:%s [%s]\n',
            host or '-', port or '-', msg or '-', dt())
    DBG('========' .. s)

    WSync2Agent.writeLocalConfig(stdin, msg)
    return msg
end

function WSync2Agent.instant:TaskLocalCountdown(
    uinput, stdout
)
    DBG("WSync2Agent.instant:Task()")

    local port = self.conf.port
    local sockfd = self.res.sockfd

    local channels = WSync2Agent.GetChannels(uinput)
    local timeouts = WSync2Agent.GetTimers(uinput)

    self.res.channels = channels
    self.res.timeouts = timeouts

    if (not self.cache.index) then
        self.cache.index = 1
    end

    DBG(sfmt("self: f %s, loop %s", self.conf.flagLoop, self.res.loops or '-'))
    DBG(sfmt("self: %s, cache.timeout = %s, cache.targe = %s",
            self.cache.index or '-',
            self.cache.timeout or '-',
            self.cache.target or '-'))

    if (channels and timeouts) then
        -- in case two table size
        local sizeChannelsList = #channels or 0
        local sizeTimeoutsList = #timeouts or 0
        local sizeMax = WSync2Agent.findMaxSize(sizeChannelsList, sizeTimeoutsList)

        -- find valid index: force between 1 to sizeChannelsList
        local i = self.cache.index
        if ((not i) or i < 0) then
            i = 1
        end

        if (i > sizeChannelsList) then
            i = sizeChannelsList

            -- tried each channel in the list
            local loops = tonumber(self.res.loops) or 0
            self.res.loops = loops + 1
        end
        -- find valid channel here
        local channel = tonumber(channels[i]) or 0


        -- find valid index: force between 1 to sizeTimeoutsList
        i = self.cache.index
        if ((not i) or i < 1) then
            i = 1
        end
        if (i > sizeTimeoutsList) then
            i = sizeTimeoutsList
        end
        -- find valid timeout
        local timeout = tonumber(timeouts[i])

        -- check cache timeout
        i = self.cache.index -- reload index, remove list size filter
        local ltimeout = tonumber(self.cache.timeout) or tonumber(timeout) or 30
        -- tried current channel
        if (ltimeout == 0) then
            -- set right index
            i = i + 1
        end

        if (ltimeout < 0 or ltimeout > timeout) then
            ltimeout = timeout
        end

        -- allow multi-loops running, or only first loop
        if (channel > 0) then
            if (self.res.loops < 1 or self.res.flagLoop) then
                DBG(sfmt('------# doing wsync [%s in %s/%ss]',
                        channel or '-', ltimeout or '-', timeout or '-'))

                -- tell all peer(s)
                local msg = sfmt('%s:%s:m_set\n', channel or '', ltimeout or '')
                self.TellEveryPeerMsg(msg)
                print('====# tell every peer(s): ' .. msg)

                -- switch channel when timeup!
                WSync2Agent.doSwitchChannel(channel, ltimeout)

                -- save stat to tmp file
                local msg = nil
                if (ltimeout > 0) then
                    msg = sfmt('> T- %s: switch to ch%s in %ss',
                            timeout or '-', channel or '-', ltimeout or '-')
                else
                    msg = sfmt('# NOW! Switching CHANNEL %s ...',
                            channel or '-')
                end
                WSync2Agent.sayStatusAppend(stdout, msg)

                -- save for next loop
                ltimeout = ltimeout - 1
                self.cache.target = channel
                self.cache.timeout = ltimeout
            else
                DBG('------# single loop done (reason: single/no multi-loop)')
                local msg = '::m_hold'
                local status = '- idle (reason: single/no multi-loop)'
                WSync2Agent.freeRunIdle(stdout, status, sockfd, port, msg)
            end
        else
            DBG('------# single loop done (reason: invalid next channel)')
            local msg = '0:0:m_hold'
            local status = '- idle (reason: invalid next channel)'
            WSync2Agent.freeRunIdle(stdout, status, sockfd, port, msg)
        end

        -- save index
        self.cache.index = i
    else
        DBG('------# bad channels or timeouts list (reason invalid channels/timeouts)')

        local msg = '::m_hold'
        local status = '- idle (reason invalid channels/timeouts)'
        WSync2Agent.freeRunIdle(stdout, status, sockfd, port, msg)
    end
    
    print(sfmt('-------- -------- [%s] -------- --------', dt()))
end

function WSync2Agent.instant:TellEveryPeerMsg(msg)
    local sockfd = self.res.sockfd
    local port = self.res.port
    if (sockfd and port) then
        WSync2Agent.Comm.TellEveryPeerMsg(sockfd, port, msg)
    end
end

function WSync2Agent.doSwitchChannel(channel, ltimeout)
    if (channel and ltimeout) then
        local ltval = tonumber(ltimeout)
        if (ltval < 1) then
            DBG(sfmt('==========# switch to channel %s ...', channel))
            ARNMngr.SAFE_SET('channel', channel)
        end
    end
end


-- TODO: send stop & clear three times
function WSync2Agent.instant:Cleanup()
    if (self.res.sockfd) then
        DBG('----# closing sockfd')
        WSync2Agent.Comm.Close(self.res.sockfd)
        self.res.sockfd = nil
    end
end

function WSync2Agent.instant:Idle(sec)
    exec('sleep ' .. sec or 1)
end

function WSync2Agent.instant:tokenGenerate()
    local arn_safe = ARNMngr.SAFE_GET()
    local devWmac = arn_safe.abb_safe.wmac or '-'

    local fmtTokenKey = WSync2Agent.conf.fmtTokenKey
    local tokenKey = sfmt(fmtTokenKey, devWmac)

    local token = TOKEN.WSyncToken(tokenKey)

    DBG(sfmt('token=%s,key=%s', token, tokenKey))

    return token
end

return WSync2Agent
