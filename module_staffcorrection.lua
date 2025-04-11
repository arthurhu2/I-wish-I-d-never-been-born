--------------------------------------------------------------------------------
-- Module: StaffCorrection
-- "Beyond Final": ASCII-lower, single global cache, unrolled loops, bitmasks.
--------------------------------------------------------------------------------

local p = {}

-- 1) Load raw data
local rawStaffNames = mw.loadData('Module:StaffCorrection/data')
local rawExceptions = mw.loadData('Module:StaffCorrection/exceptions')
local rawPseudonyms = mw.loadData('Module:StaffCorrection/pseudonyms')

-- 2) Minimal ASCII-lower mechanism (A-Z => a-z)
local asciiMap = {}
for i = 0, 255 do
    local c = string.char(i)
    if i >= 65 and i <= 90 then
        asciiMap[c] = string.char(i + 32)
    else
        asciiMap[c] = c
    end
end

local function asciiLower(s)
    local n = #s
    if n == 0 then
        return s
    end
    local t = {}
    for i=1,n do
        local c = s:sub(i,i)
        t[i] = asciiMap[c] or c
    end
    return table.concat(t)
end

-- 3) Bitmask flags
local bit = bit or require('bit32')
local band, bor = bit.band, bit.bor

local EXC_FLAG = 1  -- exception
local PSE_FLAG = 2  -- pseudonym
local UNC_FLAG = 4  -- uncredited

local function isException(f)  return band(f, EXC_FLAG) ~= 0 end
local function isPseudonym(f)  return band(f, PSE_FLAG) ~= 0 end
local function isUncredited(f) return band(f, UNC_FLAG) ~= 0 end

-- 4) Unified data table
local compiledData = {}

local function ensureEntry(lc)
    local e = compiledData[lc]
    if not e then
        e = { corrected = lc, flags = 0 }
        compiledData[lc] = e
    end
    return e
end

-- 4a) Staff corrections
for orig, corr in pairs(rawStaffNames) do
    local lower = asciiLower(orig)
    ensureEntry(lower).corrected = corr
end

-- 4b) Exceptions
for i=1, #rawExceptions do
    local e = ensureEntry(asciiLower(rawExceptions[i]))
    e.flags = bor(e.flags, EXC_FLAG)
end

-- 4b2) Also mark an entry as EXC_FLAG if its *corrected* name is in exceptions
for lcName, entry in pairs(compiledData) do
    local corrLower = asciiLower(entry.corrected)
    local corrEntry = compiledData[corrLower]
    if corrEntry and band(corrEntry.flags, EXC_FLAG) ~= 0 then
        entry.flags = bor(entry.flags, EXC_FLAG)
    end
end

-- 4c) Pseudonyms
for i=1, #rawPseudonyms do
    local e = ensureEntry(asciiLower(rawPseudonyms[i]))
    e.flags = bor(e.flags, PSE_FLAG)
end

-- 4d) Uncredited/n/a
do
    local uncList = {'uncredited','n/a'}
    for i=1,2 do
        local e = ensureEntry(asciiLower(uncList[i]))
        e.flags = bor(e.flags, UNC_FLAG)
    end
end

-- 5) Trim + isBlank
local function trimInPlace(s)
    if not s or s=='' then return '' end
    local start, finish = 1, #s
    while start <= finish and s:find('^[ \t\n\r]', start) do
        start = start + 1
    end
    while finish >= start and s:find('^[ \t\n\r]', finish) do
        finish = finish - 1
    end
    if start > finish then return '' end
    return s:sub(start, finish)
end

local function isBlank(s)
    return (not s) or s=='' or (not s:find('%S'))
end

-- 6) Global cache
local globalCache = {}

-- 7) staffLinkAndCategory => single name + subcat => link, cat
local function breakLink(name)
    if #name>4 and name:sub(1,2)=="[[" then
        local barPos = name:find('|',3,true)
        if barPos then
            local endPos = name:find(']]', barPos+1, true)
            if endPos then
                return name:sub(barPos+1, endPos-1)
            else
                return name:sub(barPos+1)
            end
        else
            local endPos = name:find(']]',3,true)
            if endPos then
                return name:sub(3, endPos-1)
            else
                return name:sub(3)
            end
        end
    end
    return name
end

local function staffLinkAndCategory(originalName, subcat)
    if isBlank(originalName) then
        return '', ''
    end
    local key = "L|"..originalName.."|"..(subcat or '')
    local cVal = globalCache[key]
    if cVal then
        return cVal[1], cVal[2]
    end

    local name  = trimInPlace(originalName)
    local shown = breakLink(name)
    local lower = asciiLower(shown)
    local info  = compiledData[lower]
    if not info then
        info = { corrected=shown, flags=0 }
    end
    local cName, flags = info.corrected, info.flags

    if isUncredited(flags) then
        globalCache[key] = {'Uncredited',''}
        return 'Uncredited',''
    end

    local outLink
    if (cName~=shown) and isException(flags) then
        if subcat=='Creator' then
            outLink = '[['..cName..'|'..cName..']]'
        else
            outLink = '[['..cName..'|'..cName..']] (credited under different name)'
        end
    else
        outLink = '[['..cName..'|'..shown..']]'
    end

    local cat = ''
    if not isBlank(subcat) then
        if isPseudonym(flags) then
            cat = '[[Category:'..shown..'/'..subcat..']]'
        else
            cat = '[[Category:'..cName..'/'..subcat..']]'
        end
    end

    globalCache[key] = { outLink, cat }
    return outLink, cat
end

-- 8) p.lua_get_corrected_name
function p.lua_get_corrected_name(name)
    if isBlank(name) then
        return '', false, false
    end
    name = trimInPlace(name)
    local lower = asciiLower(name)
    local info  = compiledData[lower]
    if not info then
        return name, false, false
    end
    local f = info.flags
    return info.corrected, (band(f,EXC_FLAG)~=0), (band(f,PSE_FLAG)~=0)
end

-- 9) p.get_corrected_name
function p.get_corrected_name(frame)
    local nm = frame.args[1]
    if isBlank(nm) then
        return ''
    end
    nm = trimInPlace(nm)
    local info = compiledData[asciiLower(nm)]
    if info then
        return info.corrected
    end
    return nm
end

-- 10) p.lua_get_staff_link_and_category
function p.lua_get_staff_link_and_category(nm, sc)
    return staffLinkAndCategory(nm, sc)
end

-- 11) p.lua_get_list_of_staff => semicolon-split
local function manualSplitSemicolons(s)
    local arr, idx, start = {}, 1, 1
    while true do
        local sep = s:find(';', start, true)
        if not sep then
            arr[idx] = s:sub(start)
            break
        end
        arr[idx] = s:sub(start, sep-1)
        idx = idx + 1
        start = sep + 1
    end
    return arr
end

function p.lua_get_list_of_staff(list, subcat)
    if isBlank(list) then
        return '', {}
    end
    local key = "S|"..list.."|"..(subcat or '')
    local cVal = globalCache[key]
    if cVal then
        return cVal[1], cVal[2]
    end

    if not list:find(';',1,true) then
        local ln, cat = staffLinkAndCategory(list, subcat)
        local catArr = {}
        if cat ~= '' then catArr[1] = cat end
        globalCache[key] = { ln, catArr }
        return ln, catArr
    end

    local items = manualSplitSemicolons(list)
    local n = #items
    local lnArr, catArr = {}, {}
    for i=1,n do
        local l, c = staffLinkAndCategory(items[i], subcat)
        lnArr[#lnArr+1] = l
        if c ~= '' then
            catArr[#catArr+1] = c
        end
    end

    local combined = table.concat(lnArr, ', ')
    globalCache[key] = { combined, catArr }
    return combined, catArr
end

function p.get_list_of_staff(frame)
    local val = frame.args[1]
    local sc  = frame.args[2]
    local ln, ct = p.lua_get_list_of_staff(val, sc)
    if #ct == 0 then
        return ln
    end
    local out = ln
    for i=1,#ct do
        out = out .. ct[i]
    end
    return out
end

-- 12) p.lua_get_list_of_staff_from_args
do
    local function doOne(v, sc, lnArr, catArr)
        if v and v:find('%S') then
            local l,c = staffLinkAndCategory(v, sc)
            if l ~= '' then
                lnArr[#lnArr+1] = l
                if c ~= '' then
                    catArr[#catArr+1] = c
                end
            end
        end
    end

    local function parseArgs(a, f, sc)
        local firstVal = a[f..1]
        if not (firstVal and firstVal:find('%S')) then
            return {}, {}
        end
        local lnArr, catArr = {}, {}
        -- unrolled loop over possible 1..100
        doOne(a[f..1],   sc, lnArr, catArr)
        doOne(a[f..2],   sc, lnArr, catArr)
        doOne(a[f..3],   sc, lnArr, catArr)
        doOne(a[f..4],   sc, lnArr, catArr)
        doOne(a[f..5],   sc, lnArr, catArr)
        doOne(a[f..6],   sc, lnArr, catArr)
        doOne(a[f..7],   sc, lnArr, catArr)
        doOne(a[f..8],   sc, lnArr, catArr)
        doOne(a[f..9],   sc, lnArr, catArr)
        doOne(a[f..10],  sc, lnArr, catArr)
        doOne(a[f..11],  sc, lnArr, catArr)
        doOne(a[f..12],  sc, lnArr, catArr)
        doOne(a[f..13],  sc, lnArr, catArr)
        doOne(a[f..14],  sc, lnArr, catArr)
        doOne(a[f..15],  sc, lnArr, catArr)
        doOne(a[f..16],  sc, lnArr, catArr)
        doOne(a[f..17],  sc, lnArr, catArr)
        doOne(a[f..18],  sc, lnArr, catArr)
        doOne(a[f..19],  sc, lnArr, catArr)
        doOne(a[f..20],  sc, lnArr, catArr)
        doOne(a[f..21],  sc, lnArr, catArr)
        doOne(a[f..22],  sc, lnArr, catArr)
        doOne(a[f..23],  sc, lnArr, catArr)
        doOne(a[f..24],  sc, lnArr, catArr)
        doOne(a[f..25],  sc, lnArr, catArr)
        doOne(a[f..26],  sc, lnArr, catArr)
        doOne(a[f..27],  sc, lnArr, catArr)
        doOne(a[f..28],  sc, lnArr, catArr)
        doOne(a[f..29],  sc, lnArr, catArr)
        doOne(a[f..30],  sc, lnArr, catArr)
        doOne(a[f..31],  sc, lnArr, catArr)
        doOne(a[f..32],  sc, lnArr, catArr)
        doOne(a[f..33],  sc, lnArr, catArr)
        doOne(a[f..34],  sc, lnArr, catArr)
        doOne(a[f..35],  sc, lnArr, catArr)
        doOne(a[f..36],  sc, lnArr, catArr)
        doOne(a[f..37],  sc, lnArr, catArr)
        doOne(a[f..38],  sc, lnArr, catArr)
        doOne(a[f..39],  sc, lnArr, catArr)
        doOne(a[f..40],  sc, lnArr, catArr)
        doOne(a[f..41],  sc, lnArr, catArr)
        doOne(a[f..42],  sc, lnArr, catArr)
        doOne(a[f..43],  sc, lnArr, catArr)
        doOne(a[f..44],  sc, lnArr, catArr)
        doOne(a[f..45],  sc, lnArr, catArr)
        doOne(a[f..46],  sc, lnArr, catArr)
        doOne(a[f..47],  sc, lnArr, catArr)
        doOne(a[f..48],  sc, lnArr, catArr)
        doOne(a[f..49],  sc, lnArr, catArr)
        doOne(a[f..50],  sc, lnArr, catArr)
        doOne(a[f..51],  sc, lnArr, catArr)
        doOne(a[f..52],  sc, lnArr, catArr)
        doOne(a[f..53],  sc, lnArr, catArr)
        doOne(a[f..54],  sc, lnArr, catArr)
        doOne(a[f..55],  sc, lnArr, catArr)
        doOne(a[f..56],  sc, lnArr, catArr)
        doOne(a[f..57],  sc, lnArr, catArr)
        doOne(a[f..58],  sc, lnArr, catArr)
        doOne(a[f..59],  sc, lnArr, catArr)
        doOne(a[f..60],  sc, lnArr, catArr)
        doOne(a[f..61],  sc, lnArr, catArr)
        doOne(a[f..62],  sc, lnArr, catArr)
        doOne(a[f..63],  sc, lnArr, catArr)
        doOne(a[f..64],  sc, lnArr, catArr)
        doOne(a[f..65],  sc, lnArr, catArr)
        doOne(a[f..66],  sc, lnArr, catArr)
        doOne(a[f..67],  sc, lnArr, catArr)
        doOne(a[f..68],  sc, lnArr, catArr)
        doOne(a[f..69],  sc, lnArr, catArr)
        doOne(a[f..70],  sc, lnArr, catArr)
        doOne(a[f..71],  sc, lnArr, catArr)
        doOne(a[f..72],  sc, lnArr, catArr)
        doOne(a[f..73],  sc, lnArr, catArr)
        doOne(a[f..74],  sc, lnArr, catArr)
        doOne(a[f..75],  sc, lnArr, catArr)
        doOne(a[f..76],  sc, lnArr, catArr)
        doOne(a[f..77],  sc, lnArr, catArr)
        doOne(a[f..78],  sc, lnArr, catArr)
        doOne(a[f..79],  sc, lnArr, catArr)
        doOne(a[f..80],  sc, lnArr, catArr)
        doOne(a[f..81],  sc, lnArr, catArr)
        doOne(a[f..82],  sc, lnArr, catArr)
        doOne(a[f..83],  sc, lnArr, catArr)
        doOne(a[f..84],  sc, lnArr, catArr)
        doOne(a[f..85],  sc, lnArr, catArr)
        doOne(a[f..86],  sc, lnArr, catArr)
        doOne(a[f..87],  sc, lnArr, catArr)
        doOne(a[f..88],  sc, lnArr, catArr)
        doOne(a[f..89],  sc, lnArr, catArr)
        doOne(a[f..90],  sc, lnArr, catArr)
        doOne(a[f..91],  sc, lnArr, catArr)
        doOne(a[f..92],  sc, lnArr, catArr)
        doOne(a[f..93],  sc, lnArr, catArr)
        doOne(a[f..94],  sc, lnArr, catArr)
        doOne(a[f..95],  sc, lnArr, catArr)
        doOne(a[f..96],  sc, lnArr, catArr)
        doOne(a[f..97],  sc, lnArr, catArr)
        doOne(a[f..98],  sc, lnArr, catArr)
        doOne(a[f..99],  sc, lnArr, catArr)
        doOne(a[f..100], sc, lnArr, catArr)

        return lnArr, catArr
    end

    function p.lua_get_list_of_staff_from_args(args, fieldName, subcat)
        return parseArgs(args, fieldName, subcat)
    end

    function p.get_list_of_staff_from_args(frame)
        local a  = frame.args
        local f  = a[1]
        local sc = a[2]

        local kp = {}
        for i=1,100 do
            kp[i] = a[f..i] or ''
        end
        local bigKey = "A|"..table.concat(kp, '\0').."|"..(sc or '')
        local cached = globalCache[bigKey]
        if cached then
            return cached
        end

        local lnArr, catArr = parseArgs(a, f, sc)
        local out = table.concat(lnArr, ', ')
        for i=1,#catArr do
            out = out .. catArr[i]
        end

        globalCache[bigKey] = out
        return out
    end
end

-- 13) p.lua_get_creators
function p.lua_get_creators(list)
    if isBlank(list) then
        return '', ''
    end
    return p.lua_get_list_of_staff(list, 'Creator')
end

return p