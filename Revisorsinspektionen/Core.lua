-- Retired (pack v1.17.0): Bokföring 0.6.4 takes Skatteverket's guild tax off
-- sales itself, so the old Revisorsinspektionen counted the tax twice. The
-- pack still ships this empty copy so an update writes over the old code in
-- folders WowUp leaves behind. It does nothing, and switches itself off for
-- the next login so it stops loading at all.
local function Off()
	if C_AddOns and C_AddOns.DisableAddOn then
		C_AddOns.DisableAddOn("Revisorsinspektionen")
	elseif DisableAddOn then
		DisableAddOn("Revisorsinspektionen")
	end
end
pcall(Off)
