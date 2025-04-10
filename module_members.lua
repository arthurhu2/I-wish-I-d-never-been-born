local p = {}
local h = require('Module:HF')
local module_reality = require('Module:Reality').lua_get_name_and_reality
local standard = require('Module:StandardizedName').name_for_sorting
local mwtitle = mw.title
local getCurrentTitle = mwtitle.getCurrentTitle
local getArgs = require('Dev:Arguments').getArgs
local Link, Category, isempty = h.Link, h.Category, h.isempty
local sfind, sgsub = string.find, string.gsub
local tconcat = table.concat

--------------------------------------------------------------------------------
-- used in Template:Member of
function p.main(frame)
	local pagename = getCurrentTitle().text
	local args = getArgs(frame)
	local team = args[1]
	local team_name = args[2]

	local _, reality_info1 = module_reality(pagename)
	-- exception for The 198 team
	if team == '198' then
		team = team .. ' (' .. reality_info1.name .. ')'
	end

	local name2, reality2 = module_reality(team)

	if isempty(team_name) then
		team_name = name2
	end

	if reality_info1 ~= '' and reality2 == '' then
		team = team .. ' (' .. reality_info1.name .. ')'
	end

	return Link(team, team_name) .. Category(team .. '/Members')
end


--------------------------------------------------------------------------------
-- used in Template:Members Category
function p.members_category(frame)
	local titleObj = getCurrentTitle()
	local baseText = titleObj.baseText
	local subpageText = titleObj.subpageText
	local name, reality_info = module_reality(baseText)
	local output = { '{{DEFAULTSORT:', standard({ baseText }), subpageText, '|noerror}}' }

	if subpageText == 'Members' then
		local design   = require('Module:Design')
		local pageType = require('Module:PageType')
		output[#output + 1] = design.messagebox({
			'Members of the ' .. Link(baseText, baseText) .. '.'
		})
		local cat = Category(name .. ' members')
		local pt  = pageType.get_page_type(baseText)
		if reality_info ~= '' then
			if pt == 'Organization' then
				cat = cat .. Category(reality_info.name .. '/Organizations')
			else
				cat = cat .. Category(reality_info.name .. '/Teams')
			end
		end
		output[#output + 1] = cat
	elseif sfind(baseText, ' members', 1, true) then
		local design = require('Module:Design')
		output[#output + 1] = design.messagebox({
			'Members of the ' ..
			Link(sgsub(baseText, ' members', '')) ..
			' from various realities.'
		})
		output[#output + 1] = Category('Member Lists')
	end

	return frame:preprocess(tconcat(output))
end

return p
