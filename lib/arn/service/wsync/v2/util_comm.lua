-- by Qige <qigezhao@gmail.com>
-- 2017.12.08 

local DBG = print
--local DBG = function(msg) end

local Socket = require 'socket'
local ARNMngr = require 'arn.device.mngr'

local sfmt = string.format
local tbl_push = table.insert


local WSync2Comm = {}

function WSync2Comm.Env()
    return (1 and Socket)
end

function WSync2Comm.Socket(timeout, port, protocol)
    local sockfd = Socket.udp()    
    if (not sockfd) then
        DBG('### udp() failed')
        return nil
    end
    
    local ret = sockfd:settimeout(timeout or 0.1)
    if (not ret) then
        DBG('### settimeout() failed')
        sockfd:close()
        return nil
    end
    ret = sockfd:setsockname('*', tonumber(port))
    if (not ret) then
        DBG('### setsockname() failed')
        sockfd:close()
        return nil
    end
    
    return sockfd
end

function WSync2Comm.fetchAllPeersIP()
    local hosts = {}
    tbl_push(hosts, '192.168.1.165')
    return hosts
end

function WSync2Comm.HearFromAllPeers(sockfd, length)
    local msg = nil
    local host = nil
    local port = nil
    if (sockfd) then
        msg, host, port = sockfd:receivefrom(tonumber(length) or 16)
    end
    return msg, host, port
end

-- TODO: get each peer(s) wmac, call rarp, conver to ip
-- send msg to each of them
function WSync2Comm.TellEveryPeerMsg(sockfd, port, msg)
    DBG('--------# TellEveryPeerMsg')
    if (sockfd and msg) then
        DBG(sfmt('==========# tell all peers: %s', msg))
        local hosts = WSync2Comm.fetchAllPeersIP()
        if (hosts) then
            for _,host in ipairs(hosts) do
                WSync2Comm.tellPeerMsg(sockfd, host, tonumber(port) or 3003, msg)
            end
        end
    else
        DBG('--------# invalid socket or msg')
    end
end

function WSync2Comm.tellPeerMsg(sockfd, host, port, msg)
    if (sockfd and host and port and msg) then
        DBG(sfmt('==> send [%s] to %s:%s', msg, host, port))
        sockfd:sendto(msg, host, port)
    end
end

return WSync2Comm
