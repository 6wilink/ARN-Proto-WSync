-- by Qge <qigezhao@gmail.com>
-- 2017.09.05, 2017.10.20 v3.0-201017

local CCFF = require 'arn.utils.ccff'
local exec = CCFF.execute
local sfmt = string.format

local Token = {}

Token.md5Fmt = 'echo -n "%s" > /tmp/.md5.token; md5sum /tmp/.md5.token | awk \'{print $1}\''

function Token.CGI(key, ttl)
    return Token.md5(key)
end

function Token.Proxy(key, ttl)
    return Token.md5(key)
end

-- use first 8 chars
function Token.WSyncToken(key)
    local result
    local md5 = Token.md5(key)
    if (md5) then
        result = string.sub(md5, 1, 8)
    end
    return result
end

function Token.md5(key)
    local md5Fmt = Token.md5Fmt
    local cmd = sfmt(md5Fmt, key)
    return exec(cmd)
end

function Token.Compare(token1, token2)
    local result = false
    if (token1 and token2) then
        if (token1 == token2) then
            result = true
        end
    end
    return result
end

return Token