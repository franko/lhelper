-- MD5 message digest, pure Lua 5.4 implementation (uses integer bitwise
-- operators). Used to compute the build environment digest, replacing the
-- external md5sum command.

local md5 = {}

local K = {}
for i = 1, 64 do
    K[i] = math.floor(math.abs(math.sin(i)) * 2^32) & 0xffffffff
end

local S = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
}

local function rotl(x, n)
    x = x & 0xffffffff
    return ((x << n) | (x >> (32 - n))) & 0xffffffff
end

function md5.sumhexa(message)
    local a0, b0, c0, d0 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476

    local msg_len = #message
    local padding = ("\128") .. ("\0"):rep((55 - msg_len) % 64)
    message = message .. padding .. string.pack("<I8", msg_len * 8)

    for chunk_start = 1, #message, 64 do
        local M = { string.unpack("<I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4",
            message, chunk_start) }
        local A, B, C, D = a0, b0, c0, d0
        for i = 0, 63 do
            local F, g
            if i < 16 then
                F = (B & C) | (~B & D)
                g = i
            elseif i < 32 then
                F = (D & B) | (~D & C)
                g = (5 * i + 1) % 16
            elseif i < 48 then
                F = B ~ C ~ D
                g = (3 * i + 5) % 16
            else
                F = C ~ (B | (~D & 0xffffffff))
                g = (7 * i) % 16
            end
            F = (F + A + K[i + 1] + M[g + 1]) & 0xffffffff
            A = D
            D = C
            C = B
            B = (B + rotl(F, S[i + 1])) & 0xffffffff
        end
        a0 = (a0 + A) & 0xffffffff
        b0 = (b0 + B) & 0xffffffff
        c0 = (c0 + C) & 0xffffffff
        d0 = (d0 + D) & 0xffffffff
    end

    local digest = string.pack("<I4I4I4I4", a0, b0, c0, d0)
    return (digest:gsub(".", function(c)
        return string.format("%02x", string.byte(c))
    end))
end

return md5
