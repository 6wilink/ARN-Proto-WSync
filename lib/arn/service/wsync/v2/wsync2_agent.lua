-- by Qige <qigezhao@gmail.com>
-- 2017.10.20 ARN iOMC v3.0-alpha-201017Q

local DBG = print
--local DBG = function(msg) end

local DBG_COMM = print
--local DBG_COMM = function(msg) end

local Socket    = require 'socket'
local CCFF      = require 'arn.utils.ccff'
local ARNMngr   = require 'arn.device.mngr'
local TOKEN     = require 'arn.service.wsync.v2.util_token'
local RARP      = require 'arn.utils.rarp'

local exec  = CCFF.execute
local ssplit = CCFF.split
local fwrite = CCFF.file.write
local fread = CCFF.file.read
local striml = CCFF.triml
local sfmt  = string.format
local schar = string.char
local sbyte = string.byte
local ssub  = string.sub
local ts    = os.time
local dt    = function() return os.date('%X %x') end


local WSync2Agent = {}
WSync2Agent.VERSION = 'ARN-Agent-WSync v2.0-alpha-20171206Q'

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

function WSync2Agent.instant:Prepare(timeout, port)
    DBG(sfmt("Agent.instant:Prepare(%s)", timeout or '-'))
    
    if ((not ARNMngr) or (not RARP)) then
        return 'error: need packet ARN-Scripts'
    end
    
    -- enable run again & again
    if (self.conf.flagLoop == 'on' and self.conf.flagLoop == '1') then
        self.conf.flagLoop = 1
    else
        self.conf.flagLoop = 0
    end
    
    -- init socket
    if (not Socket) then
        return 'error: need packet luasocket'
    end
    local sockfd = Socket.udp()
    if (not sockfd) then
        return 'error: bad local socket'
    end
    local ret = sockfd:settimeout(timeout or 0.1)
    if (not ret) then
        sockfd:close()
        return 'error: set socket opt(timeout) failed'
    end
    ret = sockfd:setsockname('*', port)
    if (not ret) then
        sockfd:close()
        return 'error: set socket opt(bind) failed'
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
    self.cache.index = 1
end

function WSync2Agent.instant:BroadcastGoodbye()
    DBG('------# say goodbye too all peers')
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

function WSync2Agent.SayStatusWorking(path, s)
    local msg = sfmt('- (%s) idle at %s\n', s or '-', dt())
    fwrite(path, msg)
    
    print(msg)
end

function WSync2Agent.instant:Task(
    channels, timeouts, 
    stdout
)
    DBG("WSync2Agent.instant:Task()")

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
        local channel = channels[i]


        -- find valid index: force between 1 to sizeTimeoutsList
        i = self.cache.index
        if ((not i) or i < 1) then
            i = 1
        end
        if (i > sizeTimeoutsList) then
            i = sizeTimeoutsList
        end
        -- find valid timeout
        local timeout = timeouts[i]
        
        -- check cache timeout
        local ltimeout = tonumber(self.cache.timeout) or tonumber(timeout) or 30
        -- tried current channel
        if (ltimeout == 0) then
            -- set index
            i = i + 1
        end

        if (ltimeout < 0) then
            ltimeout = timeout
        end
        
        -- allow multi-loops running, or only first loop
        if (self.res.loops < 1 or self.res.flagLoop) then
            local sockfd = self.res.sockfd
            DBG(sfmt('------# doing wsync [%s in %s/%ss]', 
                    channel or '-', ltimeout or '-', timeout or '-'))
            WSync2Agent.singleBroadcast(sockfd, channel, ltimeout, stdout)
            WSync2Agent.doSwitchChannel(channel, ltimeout)
            
            -- save for next loop
            ltimeout = ltimeout - 1
            self.cache.target = channel
            self.cache.timeout = ltimeout
        else
            DBG('------# single loop done (b)')
            WSync2Agent.SayStatusWorking(stdout, 'b')
        end

        -- save index
        self.cache.index = i
    else
        DBG('------# bad channels or timeouts list (a)')
        WSync2Agent.SayStatusWorking(stdout, 'a')
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

function WSync2Agent.instant:BroadcastGoodbye()
    DBG('--------# say goodbye to all peers')
    WSync2Agent.broadcastAll(self.res.sockfd, '::m_reset')
end

-- TODO: get each peer(s) wmac, call rarp, conver to ip
-- send msg to each of them
function WSync2Agent.broadcastAll(sockfd, msg)
    if (sockfd and msg) then
        DBG(sfmt('==========# broadcast to all peers: %s', msg))
    else
        DBG('--------# invalid socket or msg')
    end
end

-- handle single channel switching within timeout
function WSync2Agent.singleBroadcast(sockfd, channel, timeout)
    if (sockfd) then
        local msg = '::m_set'
        if (channel and timeout) then
            local ch = tonumber(channel)
            local to = tonumber(timeout)
            DBG(sfmt('--------# msg: -> ch%s in %ss', ch, to))            
            msg = sfmt('%s:%s:m_set', ch, to)
        else
            DBG('========# cancel all')
        end
        WSync2Agent.broadcastAll(sockfd, msg)
    else
        DBG('--------# invalid socket, channel or timeout value')
        WSync2Agent.SayStatusWorking(stdout, 'e')
    end
end

function WSync2Agent.idle(sec)
    if (sec) then
        Socket.sleep(sec)
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