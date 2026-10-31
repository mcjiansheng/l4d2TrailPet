// Change these values, then rebuild the VPK. Units are Source units and seconds.
// The model is present in the user's base-game pak01_dir.vpk.
::TrailPet.Config <- {
    model = "models/props_junk/gnome.mdl"
    // Think each engine frame; distance is based on elapsed server time.
    tick = 0.0
    speed = 220.0
    followDistance = 95.0
    rescueDistance = 850.0
    rescueDelay = 3.0
    // MDL hull bounds: (-12.82,-0.50,-11.39)..(1.80,16.39,23.33).
    // The origin is inside the gnome, so raise it above the ground reference.
    modelLift = 14.0
    modelYawOffset = 180.0
    // Yaw-rotated MDL hull reaches 20.807 units from the model origin.
    radius = 21.0
    height = 48.0
    stepHeight = 18.0
    // Keep landing turns inside the narrow stairwell instead of cutting rails.
    trailSpacing = 8.0
    trailLimit = 100
    stallSeconds = 25.0
    progressDistance = 65.0
    guideCooldown = 45.0
    guideDuration = 9.0
    guideRange = 420.0
    interactDistance = 125.0
    maxPets = 8
};
