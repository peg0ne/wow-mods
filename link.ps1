# Links every addon in this repo (a folder with a .toc of the same name) into
# the WoW AddOns folder as a directory junction, so the game loads the files
# straight from the repo. Junctions need no admin rights. Safe to re-run:
# existing links are left alone, and a real folder with the same name is
# never touched.
param(
	[string]$AddOns = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
)

if (-not (Test-Path $AddOns)) { throw "AddOns folder not found: $AddOns" }

Get-ChildItem -Path $PSScriptRoot -Directory | Where-Object {
	Test-Path (Join-Path $_.FullName "$($_.Name).toc")
} | ForEach-Object {
	$target = Join-Path $AddOns $_.Name
	$existing = Get-Item $target -ErrorAction SilentlyContinue
	if (-not $existing) {
		New-Item -ItemType Junction -Path $target -Target $_.FullName | Out-Null
		Write-Output "linked   $($_.Name)"
	} elseif ($existing.LinkType -eq "Junction" -and $existing.Target -contains $_.FullName) {
		Write-Output "ok       $($_.Name)"
	} else {
		Write-Warning "skipped  $($_.Name): $target already exists and is not a link to this repo"
	}
}
