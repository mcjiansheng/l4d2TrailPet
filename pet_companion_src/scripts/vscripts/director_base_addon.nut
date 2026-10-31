// L4D2 additive VScript entry point, also used by Left 4 Bots 2.
// Keep the implementation in a unique namespace; do not replace director options.
printl("[TrailPet] BOOT 0.2.4: director_base_addon");
try
{
    if (!IncludeScript("trailpet/main", getroottable())) throw "main.nut could not be included";
}
catch (e)
{
    printl("[TrailPet] BOOT FAILED: " + e);
    try { StringToFile("trailpet_boot_error.txt", "BOOT FAILED: " + e); } catch (_) {}
}
