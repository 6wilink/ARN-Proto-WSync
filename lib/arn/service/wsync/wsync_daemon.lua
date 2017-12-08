-- by Qige <qigezhao@gmail.com>
-- 2017.12.06 ARN-Proto-WSync

-- DEBUG USE ONLY
--local DBG = print
local function DBG(msg) end

local CCFF = require 'arn.utils.ccff'
local WSyncAgent = require 'arn.service.wsync.v2.wsync2b_agent'

local cget  = CCFF.conf.get
local ssplit = CCFF.split
local fread = CCFF.file.read
local fwrite = CCFF.file.write

local ts    = os.time
local dt    = function() return os.date('%X %x') end
local sfmt  = string.format


local WSync = {}

WSync.conf = {}
WSync.conf._SIGNAL = '/tmp/.signal.wsync2.tmp'
WSync.conf._SWAP1 = '/tmp/.conf.wsync2.tmp'
WSync.conf._SWAP2 = '/tmp/.stat.wsync2.tmp'
WSync.conf.enabled = cget('arn-wsyncd','v2','enabled') or '0'
WSync.conf.flagLoop = cget('arn-wsyncd','v2','loop') or '0'
WSync.conf.protocol = cget('arn-wsyncd','v2','protocol') or 'udp'
WSync.conf.port = cget('arn-wsyncd','v2','port') or 3003
--WSync.conf.interval = 5--cget('arn-wsyncd','v2','interval') or 1
WSync.conf.interval = cget('arn-wsyncd','v2','interval') or 1
WSync.conf.channel = nil
WSync.conf.timeout = nil
WSync.conf._STDOUT = nil

function WSync.version()
    WSync.reply(sfmt('-> %s', WSync.VERSION))
end

function WSync.init()
    -- default disabled
    if (WSync.conf.enabled ~= 'on' and WSync.conf.enabled ~= '1') then
        return 'Agent-WSync disabled'
    end
    
    -- check depend package
    if (not CCFF) then
        return 'need packet ARN-Scripts'
    end
    
    -- check swap file config
    if (not WSync.conf._SWAP1) or (not WSync.conf._SWAP2) then
        return 'bad wsync input/output'
    end
    WSync.conf._STDOUT = WSync.conf._SWAP2
    
    -- check depend package
    if (not WSyncAgent) then
        return 'unknown agent'
    end

    -- mark version
    WSync.VERSION = WSyncAgent.VERSION

    return nil
end

-- boot(), user input, m_set will call this
function WSync.triggerReset(params, paramsLast)
    if ((not params) or (not paramsLast)) then
        DBG(sfmt('### empty %s/%s', params or '-', paramsList or '-'))
        return true
    end
    
    if (paramsLast) then
        if (params == '' or params == '\n') then
            DBG(sfmt('### valid last, but empty %s', params or '-'))
            return true
        end
        if (paramsLast ~= params) then
            DBG(sfmt('### valid last, valid this, not equal'))
            return true
        end
    end
    return false
end

function WSync.Run()
    local err = WSync.init()
    if (err) then
        WSync.failed(err)
        return
    end
    WSync.version()

    -- get agent
    local DaemonAgent = WSyncAgent.New(
        WSync.conf.port, WSync.conf.protocol, 
        WSync.conf.interval, WSync.conf.flagLoop
    )
    if (not DaemonAgent) then
        WSync.failed('unable to get agent instant')
        return
    end

    -- mark agent ready
    local msg = sfmt("-> started (%s:%s | intl %s | f %s) +%s",
        WSync.conf.protocol, WSync.conf.port,
        WSync.conf.interval, WSync.conf.flagLoop, dt()
    )
    WSync.reply(msg)
    WSync.log(msg)

    -- do some preparation: check env, utils, etc.
    local waitTO = 0.2
    local msg = DaemonAgent:Prepare(waitTO, WSync.conf.port, 
            WSync.conf.protocol)
    
    -- reset user input by writing new channels or timeouts
    local stdin = WSync.conf._SWAP1
    local stdout = WSync.conf._STDOUT
    local uinputLast = nil
    if (not msg) then
        -- ready to run, check quit signal, run task, do idle
        local i
        while true do
            -- check "quit" before do anything
            if (WSync.QUIT_SIGNAL()) then
                DaemonAgent:BroadcastGoodbye()
                break
            end
            
            -- recv msg & save
            local msg = DaemonAgent:TaskLanSync(stdin, stdout)
            if (msg) then
                WSync.reply(sfmt("====# Heard: [%s] at %s", msg or '', dt()))
            else
                WSync.reply(sfmt("====# Heard: timeout at %s", dt()))
            end
            
            -- read user input
            local uinputRaw = fread(stdin) -- ex: "21,15[,]"
            local uinput = string.gsub(uinputRaw, '\n', '')
            WSync.reply(sfmt("--> Agent-WSync: [%s] at %s", uinput or '', dt()))
            if (WSync.triggerReset(uinput, uinputLast)) then
                WSync.reply('========# triggered reset')
                DaemonAgent:AllParamsReset()
            end
            
            -- run as user requested
            DaemonAgent:TaskLocalCountdown(uinput, stdout)
            
            -- print status
            WSync.reply(sfmt("--> Agent-WSync synced +%s", dt()))
            
            DaemonAgent:Idle(WSync.conf.interval)
            uinputLast = uinput
        end
        
        -- let user know
        local s = sfmt("========# signal SIGTERM detected +%s", dt())
        WSync.reply(s)
    else
        WSync.failed(msg)
    end

    -- clean up agent
    DaemonAgent:Cleanup()

    -- mark quit
    local s = sfmt("-> stopped +%s", dt())
    WSync.reply(s)
    WSync.log(s)
end


function WSync.failed(msg)
    print('== Agent-WSync failed: ' .. msg)
end

function WSync.reply(msg)
    print(msg)
end

function WSync.log(msg)
    local sig_file = WSync.conf._SIGNAL
    fwrite(sig_file, msg .. '\n')
end

function WSync.QUIT_SIGNAL()
    local signal =  false
    local exit_array = {
        "exit","exit\n",
        "stop","stop\n",
        "quit","quit\n",
        "bye","byte\n",
        "down","down\n"
    }
    local sig_file = WSync.conf._SIGNAL
    local sig = fread(sig_file)
    for k,v in ipairs(exit_array) do
        if (sig == v) then
            signal = true
            break
        end
    end
    return signal
end

return WSync
