-- Retired (after pack v1.20.0): nobody used the shared quests (/uppdrag) or
-- Platsbanken. The pack still ships this empty copy so an update writes over
-- the old code in folders WowUp leaves behind. It does nothing, and switches
-- itself off for the next login so it stops loading at all.
local function Off()
	if C_AddOns and C_AddOns.DisableAddOn then
		C_AddOns.DisableAddOn("Arbetsformedlingen")
	elseif DisableAddOn then
		DisableAddOn("Arbetsformedlingen")
	end
end
pcall(Off)
