// Standalone L4D2 server VScript. No Left4Bots dependency or gameplay cvar edits.
// ASCII source avoids encoding problems in Source's script loader.
if ("TrailPet" in getroottable())
{
    ::TrailPet.Log("Already loaded; keeping the existing pets and callbacks.");
    return;
}
::TrailPet <- {
    version = "0.2.4", pets = {}, events = {}, thinker = null,
    nextScan = 0.0, lastTick = 0.0, nextError = 0.0, errors = 0,
    finale = false, guidePausedUntil = 0.0, logs = [], ticks = 0
};
if (!IncludeScript("trailpet/config", getroottable())) throw "config.nut could not be included";
local P = ::TrailPet;

P.Log <- function(message)
{
    local line = "[TrailPet] " + Time() + " " + message;
    printl(line);
    P.logs.append(line);
    if (P.logs.len() > 60) P.logs.remove(0);
    local map = "unknown";
    try { map = Director.GetMapName(); } catch (_) {}
    local report = "Trail Pet " + P.version + " | map=" + map + "\n";
    foreach (s in P.logs) report += s + "\n";
    // L4D2 writes below left4dead2/ems, never an arbitrary OS path.
    try { StringToFile("trailpet_status.txt", report); } catch (_) {}
};
P.Valid <- function(e) { return e != null && e.IsValid(); };
P.Distance <- function(a, b) { return (a - b).Length(); };
P.Say <- function(player, message) { ClientPrint(player, 3, "\x04[Pet]\x01 " + message); };
P.IsOwner <- function(player)
{
    return P.Valid(player) && NetProps.GetPropInt(player, "m_iTeamNum") == 2 && !IsPlayerABot(player)
        && NetProps.GetPropInt(player, "m_lifeState") == 0;
};

// Ignore monsters/players in movement probes, but include solid world, windows,
// grates and moveable props/doors. The pet itself is SOLID_NONE.
P.Trace <- function(a, b, ignore = null)
{
    local trace = { start = a, end = b, mask = 16395, ignore = ignore };
    TraceLine(trace);
    if (!("fraction" in trace)) throw "TraceLine did not return a fraction";
    return trace;
};
P.Clear <- function(a, b, ignore = null)
{
    local t = P.Trace(a, b, ignore);
    return (!("startsolid" in t) || !t.startsolid) && t.fraction >= 0.999;
};

// Multiple volume probes are used because this L4D2 build exposes TraceLine,
// not TraceHull. Failed probes stop movement; they never default to 'clear'.
P.Room <- function(pos, ignore = null)
{
    local r = P.Config.radius;
    if (!P.Clear(pos + Vector(0,0,3), pos + Vector(0,0,P.Config.height), ignore)) return false;
    // The footprint can overlap the next tread. Probe the body above a step,
    // while retaining the upper-body and overhead checks.
    foreach (z in [P.Config.stepHeight + 2.0, P.Config.height])
    {
        local c = pos + Vector(0,0,z);
        foreach (offset in [Vector(r,r,0), Vector(-r,r,0), Vector(r,-r,0), Vector(-r,-r,0)])
            if (!P.Clear(c, c + offset, ignore)) return false;
    }
    return true;
};
P.Ground <- function(pos, ignore = null)
{
    local t = P.Trace(pos + Vector(0,0,P.Config.stepHeight + 4.0), pos - Vector(0,0,52), ignore);
    if (("startsolid" in t && t.startsolid) || t.fraction >= 0.999 || !("pos" in t)) return null;
    local p = t.pos + Vector(0,0,2);
    if (!P.Room(p, ignore)) return null;
    // Small footprint must have support: do not balance the model over a ledge.
    foreach (o in [Vector(10,0,0), Vector(-10,0,0), Vector(0,10,0), Vector(0,-10,0)])
    {
        local support = P.Trace(p + o + Vector(0,0,P.Config.stepHeight + 4.0),
            p + o - Vector(0,0,P.Config.stepHeight + 4.0), ignore);
        if (("startsolid" in support && support.startsolid) || support.fraction >= 0.999
            || !("pos" in support) || abs(support.pos.z - (p.z - 2.0)) > P.Config.stepHeight) return null;
    }
    return p;
};
P.BodyClear <- function(a, b, owner)
{
    if (a.x == b.x && a.y == b.y && a.z == b.z) return true;
    // Step already raises the sweep above the higher endpoint tread.
    if (!P.Clear(a + Vector(0,0,6), b + Vector(0,0,6), owner)) return false;
    local r = P.Config.radius;
    foreach (z in [P.Config.stepHeight + 2.0, P.Config.height])
        foreach (o in [Vector(0,0,z), Vector(r,r,z), Vector(-r,r,z), Vector(r,-r,z), Vector(-r,-r,z)])
            if (!P.Clear(a + o, b + o, owner)) return false;
    return true;
};
// Only a short horizontal step: rise, advance, then settle onto checked ground.
// Long routes must use Segment so every part of the path has ground support.
P.Step <- function(a, at, owner)
{
    local b = P.Ground(at, owner);
    if (b == null || abs(b.z - a.z) > P.Config.stepHeight) return null;
    local high = a.z > b.z ? a.z : b.z;
    local up = Vector(a.x,a.y,high), over = Vector(b.x,b.y,high);
    if (high > a.z && !P.BodyClear(a,up,owner)) return null;
    if (!P.BodyClear(up,over,owner)) return null;
    if (high > b.z && !P.BodyClear(over,b,owner)) return null;
    return b;
};
P.Segment <- function(a, b, owner)
{
    local delta = b-a; delta.z = 0;
    local length = delta.Length();
    local count = ceil(length / 12.0).tointeger();
    if (count < 1) return abs(b.z-a.z) <= P.Config.stepHeight && P.Room(b,owner);
    local at = a;
    for (local i = 1; i <= count; i++)
    {
        local point = a + delta * (i.tofloat()/count);
        point.z = at.z;
        // Route visibility needs continuous ground and a body corridor.
        // Full landing room/footprint support is checked by each actual Move.
        local t = P.Trace(point + Vector(0,0,P.Config.stepHeight + 4.0), point - Vector(0,0,52), owner);
        if (("startsolid" in t && t.startsolid) || t.fraction >= 0.999 || !("pos" in t)) return false;
        local next = t.pos + Vector(0,0,2);
        if (abs(next.z-at.z) > P.Config.stepHeight) return false;
        local high = at.z > next.z ? at.z : next.z;
        local up = Vector(at.x,at.y,high), over = Vector(next.x,next.y,high);
        if (high > at.z && !P.BodyClear(at,up,owner)) return false;
        if (!P.BodyClear(up,over,owner)) return false;
        if (high > next.z && !P.BodyClear(over,next,owner)) return false;
        at = next;
    }
    return abs(at.z-b.z) <= P.Config.stepHeight;
};
P.SafeNear <- function(owner, front = false)
{
    local pos = owner.GetOrigin();
    local yaw = owner.EyeAngles().Yaw() * 0.01745329252;
    local angles = front ? [0,45,-45,90,-90,135,-135,180] : [110,-110,150,-150,90,-90,0,180];
    foreach (radius in [85.0, 60.0, 110.0, 35.0])
        foreach (degrees in angles)
        {
            local ang = yaw + degrees * 0.01745329252;
            local candidate = P.Ground(pos + Vector(cos(ang)*radius, sin(ang)*radius, 0), owner);
            if (candidate != null && P.Clear(owner.EyePosition(), candidate + Vector(0,0,20), owner)
                && P.Segment(pos + Vector(0,0,2), candidate, owner)) return candidate;
        }
    return null;
};
P.Flow <- function(pos)
{
    local f = GetFlowDistanceForPosition(pos);
    return f != null && f >= 0.0 && f < 10000000.0 ? f : null;
};

P.NewState <- function(owner)
{
    return {
        owner = owner, ent = null, pos = null, mode = "follow", disabled = false,
        trail = [], nextSpawn = Time() + 1.0, nextRescue = 0.0,
        blockedSince = -1.0, yaw = 0.0, buttons = 0, nextPet = 0.0,
        happyUntil = 0.0, progress = null, progressAt = Time(), nextGuide = Time() + 10.0,
        guideUntil = 0.0, route = [], lastMoved = Time(), nextFlow = 0.0,
        nextCommand = 0.0, spawns = 0, rescues = 0, interactions = 0,
        nextTarget = 0.0, followTarget = null, nextRoom = 0.0
    };
};
P.Remove <- function(s)
{
    if (P.Valid(s.ent)) s.ent.Kill();
    s.ent = null;
};
P.Spawn <- function(s)
{
    s.nextSpawn = Time() + 3.0;
    local at = P.SafeNear(s.owner, true);
    if (at == null) return false;
    PrecacheModel(P.Config.model);
    if (!IsModelPrecached(P.Config.model)) throw "Gnome model was not precached";
    // Override supports the game's physics-prop gnome as a decorative dynamic.
    local e = SpawnEntityFromTable("prop_dynamic_override", {
        targetname = "trailpet_" + s.owner.GetPlayerUserId(),
        model = P.Config.model, origin = at + Vector(0,0,P.Config.modelLift), angles = "0 0 0",
        solid = 0, DisableBoneFollowers = 1, disableshadows = 1,
        rendermode = 0, renderamt = 255, rendercolor = "255 235 170"
    });
    if (!P.Valid(e)) throw "prop_dynamic_override returned null";
    try
    {
        NetProps.SetPropInt(e, "m_Collision.m_nSolidType", 0);
        NetProps.SetPropInt(e, "m_takedamage", 0);
        if (NetProps.GetPropInt(e, "m_Collision.m_nSolidType") != 0) throw "solid flag verification failed";
        if (NetProps.GetPropInt(e, "m_takedamage") != 0) throw "damage flag verification failed";
    }
    catch (err) { e.Kill(); throw err; }
    s.ent = e;
    s.pos = at;
    s.trail.clear();
    s.route.clear();
    s.mode = "follow";
    s.blockedSince = -1.0;
    s.spawns++;
    P.Log("SPAWN OK user=" + s.owner.GetPlayerUserId() + " entity=" + e.GetEntityIndex()
        + " model=" + e.GetModelName() + " pos=" + at);
    P.Say(s.owner, "Your gnome is here! Look nearby + press E. Chat: !pet help");
    return true;
};
P.Scan <- function()
{
    local seen = {};
    local player = null;
    while ((player = Entities.FindByClassname(player, "player")) != null)
    {
        if (!P.IsOwner(player)) continue;
        local id = player.GetPlayerUserId();
        seen[id] <- true;
        if (!(id in P.pets) && P.pets.len() < P.Config.maxPets) P.pets[id] <- P.NewState(player);
        if (id in P.pets) P.pets[id].owner = player;
    }
    local gone = [];
    foreach (id, s in P.pets)
        if (!(id in seen)) { P.Remove(s); gone.append(id); }
    foreach (id in gone) delete P.pets[id];
};

P.RecordTrail <- function(s)
{
    local raw = s.owner.GetOrigin();
    if (s.trail.len() > 0 && P.Distance(s.trail.top(), raw) < P.Config.trailSpacing) return;
    local point = P.Ground(raw, s.owner);
    if (point == null) return;
    s.trail.append(point);
    if (s.trail.len() > P.Config.trailLimit) s.trail.remove(0);
};
P.FollowTarget <- function(s)
{
    if (P.Distance(s.pos, s.owner.GetOrigin()) < P.Config.followDistance) return null;
    if (Time() < s.nextTarget)
    {
        if (s.followTarget == null) return null;
        local remaining = s.followTarget - s.pos; remaining.z = 0;
        if (remaining.Length() >= 8.0) return s.followTarget;
    }
    s.nextTarget = Time() + 0.25;
    local tried = 0;
    // Prefer the most recent reachable breadcrumb. Corners retain older points.
    for (local i = s.trail.len() - 1; i >= 0; i--)
    {
        local p = s.trail[i];
        // Finish tight corner points; skipping them early cuts the door frame.
        if (P.Distance(p, s.pos) < 0.5) continue;
        // Denser breadcrumbs need the same search distance around a landing.
        // followDistance already keeps the pet away from its owner; a nearby
        // breadcrumb can still be the only safe way through a narrow turn.
        if (++tried > 48) break;
        if (P.Segment(s.pos, p, s.owner))
        {
            for (local j = 0; j < i; j++) s.trail.remove(0);
            s.followTarget = p;
            return p;
        }
    }
    // A direct chase must stay on a walkable route, including its floor level.
    local direct = s.owner.GetOrigin();
    s.followTarget = P.Segment(s.pos,direct,s.owner) ? direct : null;
    return s.followTarget;
};
P.Move <- function(s, target, dt)
{
    local delta = target - s.pos;
    delta.z = 0;
    local len = delta.Length();
    if (len < 0.5) return false;
    local remaining = P.Config.speed * dt;
    if (remaining > len) remaining = len;
    local direction = delta * (1.0 / len);
    local moved = false;
    while (remaining > 0.01)
    {
        local step = remaining > 12.0 ? 12.0 : remaining;
        local next = P.Step(s.pos, s.pos + direction * step, s.owner);
        if (next == null) break;
        s.pos = next;
        remaining -= step;
        moved = true;
    }
    if (!moved) return false;
    s.yaw = atan2(direction.y, direction.x) * 57.295779513;
    s.lastMoved = Time();
    return true;
};
P.Rescue <- function(s, force = false)
{
    if (!force && Time() < s.nextRescue) return false;
    s.nextRescue = Time() + 3.0;
    local at = P.SafeNear(s.owner, force);
    if (at == null) return false;
    s.pos = at;
    s.ent.SetOrigin(at + Vector(0,0,P.Config.modelLift));
    s.trail.clear();
    s.route.clear();
    s.mode = "follow";
    s.nextTarget = 0.0;
    s.followTarget = null;
    s.blockedSince = -1.0;
    s.rescues++;
    P.Log("RESCUE user=" + s.owner.GetPlayerUserId() + " pos=" + at);
    return true;
};

// Bounded graph search on connected nav areas. Reference: Left 4 Lib's
// GetAllAdjacentAreas/GetNextAreaInFlow API usage; implementation is independent.
P.GuideRoute <- function(s)
{
    local first = s.owner.GetLastKnownArea();
    if (first == null) return [];
    local startFlow = P.Flow(s.owner.GetOrigin());
    if (startFlow == null) return [];
    local queue = [{area = first, parent = -1, depth = 0}];
    local visited = {}; visited[first.GetID()] <- true;
    local best = -1, bestFlow = startFlow + 70.0;
    for (local head = 0; head < queue.len() && head < 128; head++)
    {
        local node = queue[head];
        local center = node.area.GetCenter();
        local flow = P.Flow(center);
        if (head != 0 && flow != null && flow > bestFlow && P.Distance(center, s.owner.GetOrigin()) <= P.Config.guideRange)
        { bestFlow = flow; best = head; }
        if (node.depth >= 6) continue;
        for (local dir = 0; dir < 4; dir++)
        {
            local adjacent = {};
            node.area.GetAdjacentAreas(dir, adjacent);
            foreach (area in adjacent)
            {
                local id = area.GetID();
                if (id in visited || queue.len() >= 128) continue;
                visited[id] <- true;
                local p = area.GetCenter();
                if (area.IsBlocked(2, false) || abs(p.z - center.z) > 48.0
                    || P.Distance(p, s.owner.GetOrigin()) > P.Config.guideRange) continue;
                queue.append({area = area, parent = head, depth = node.depth + 1});
            }
        }
    }
    if (best < 0) return [];
    local backwards = [];
    while (best > 0)
    {
        backwards.append(queue[best].area.GetCenter());
        best = queue[best].parent;
    }
    local route = [];
    for (local i = backwards.len()-1; i >= 0; i--) route.append(backwards[i]);
    // A connected graph alone does not prove a prop can move to its first center.
    // Do not begin a route through a closed door or an obstacle.
    if (route.len() == 0 || !P.Segment(s.pos, route[0] + Vector(0,0,2), s.owner)) return [];
    return route;
};
P.Guide <- function(s, manual = false)
{
    s.nextGuide = Time() + P.Config.guideCooldown;
    if (P.finale || Time() < P.guidePausedUntil || s.owner.IsIncapacitated())
    {
        if (manual) P.Say(s.owner, "Route hint paused during finale / Tank / incapacitation.");
        return;
    }
    local route = P.GuideRoute(s);
    if (route.len() == 0)
    {
        if (manual) P.Say(s.owner, "No safe forward route found here. Move past the door/obstacle and try again.");
        return;
    }
    s.route = route;
    s.mode = "guide";
    s.guideUntil = Time() + P.Config.guideDuration;
    P.Say(s.owner, "This way! Follow the gnome for a route hint.");
    P.Log("GUIDE user=" + s.owner.GetPlayerUserId() + " waypoints=" + route.len());
};
P.Progress <- function(s)
{
    if (Time() < s.nextFlow) return;
    s.nextFlow = Time() + 1.0;
    local f = P.Flow(s.owner.GetOrigin());
    if (f == null) return;
    // Keep the reference fixed until meaningful cumulative progress occurs.
    // Updating it every tiny movement would incorrectly classify slow walking.
    if (s.progress == null || f >= s.progress + P.Config.progressDistance || f < s.progress - 350.0)
    {
        s.progress = f;
        s.progressAt = Time();
    }
    if (s.mode == "follow" && Time() >= s.nextGuide && Time()-s.progressAt >= P.Config.stallSeconds)
    {
        if (Director.HasAnySurvivorLeftSafeArea()) P.Guide(s);
    }
};
P.Pet <- function(s)
{
    if (Time() < s.nextPet) return;
    s.nextPet = Time() + 1.5;
    s.happyUntil = Time() + 2.0;
    s.interactions++;
    P.Say(s.owner, "* happy gnome wiggle *");
};
P.Interact <- function(s)
{
    local buttons = s.owner.GetButtonMask();
    local pressed = (buttons & 32) != 0 && (s.buttons & 32) == 0;
    s.buttons = buttons;
    if (!pressed || P.Distance(s.owner.GetOrigin(), s.pos) > P.Config.interactDistance) return;
    local eye = s.owner.EyePosition();
    local delta = s.pos + Vector(0,0,20) - eye;
    local length = delta.Length();
    if (length < 0.01) return;
    local fwd = s.owner.EyeAngles().Forward();
    local dot = (delta.x*fwd.x + delta.y*fwd.y + delta.z*fwd.z) / length;
    if (dot > 0.86 && P.Clear(eye, s.pos + Vector(0,0,20), s.owner)) P.Pet(s);
};
P.Animate <- function(s, moving)
{
    local now = Time();
    local pitch = 0.0, roll = 0.0, yaw = s.yaw;
    if (now < s.happyUntil)
    {
        yaw += sin(now*8.0)*55.0;
        pitch = sin(now*12.0)*7.0;
        roll = sin(now*10.0)*7.0;
    }
    else if (moving) roll = sin(now*12.0)*3.0;
    else
    {
        local to = s.owner.GetOrigin() - s.pos;
        yaw = atan2(to.y, to.x)*57.295779513 + sin(now*1.6)*12.0;
        pitch = sin(now*2.0)*2.0;
    }
    s.ent.SetOrigin(s.pos + Vector(0,0,P.Config.modelLift));
    s.ent.SetAngles(QAngle(pitch, yaw + P.Config.modelYawOffset, roll));
};
P.Update <- function(s, dt)
{
    if (!P.IsOwner(s.owner) || s.disabled) return;
    if (!P.Valid(s.ent)) { if (Time() >= s.nextSpawn) P.Spawn(s); return; }
    P.RecordTrail(s);
    P.Interact(s);
    P.Progress(s);
    if (s.mode == "guide" && Time() >= s.guideUntil) { s.mode = "follow"; s.route.clear(); }
    local target = null;
    if (s.mode == "guide")
    {
        while (s.route.len() && P.Distance(s.pos, s.route[0]) < 30.0) s.route.remove(0);
        if (s.route.len()) target = s.route[0];
    }
    else if (s.mode == "follow") target = P.FollowTarget(s);
    local moving = false;
    local needsMove = target != null || (s.mode == "follow"
        && P.Distance(s.pos,s.owner.GetOrigin()) >= P.Config.followDistance);
    if (needsMove && Time() >= s.happyUntil)
    {
        if (target != null) moving = P.Move(s, target, dt);
        if (moving) s.blockedSince = -1.0;
        else if (s.blockedSince < 0.0) s.blockedSince = Time();
        if (s.blockedSince >= 0.0 && Time()-s.blockedSince >= P.Config.rescueDelay)
        {
            if (s.mode == "guide") { s.mode = "follow"; s.route.clear(); s.blockedSince = -1.0; }
            else P.Rescue(s);
        }
    }
    else s.blockedSince = -1.0;
    if (s.mode != "stay" && P.Distance(s.pos, s.owner.GetOrigin()) > P.Config.rescueDistance) P.Rescue(s);
    // A closing door / moving elevator can invalidate a formerly safe position.
    // In that case recover to a newly checked spot, rather than remaining in it.
    if (Time() >= s.nextRoom)
    {
        s.nextRoom = Time() + 0.25;
        if (!P.Room(s.pos, s.owner))
            if (!P.Rescue(s)) { P.Remove(s); s.nextSpawn = Time() + 1.0; return; }
    }
    P.Animate(s, moving);
};
P.Status <- function(s)
{
    local text = "v" + P.version + " mode=" + s.mode + " visible=" + P.Valid(s.ent)
        + " ticks=" + P.ticks + " errors=" + P.errors + " spawns=" + s.spawns
        + " rescues=" + s.rescues + " interactions=" + s.interactions;
    if (P.Valid(s.ent)) text += " solid=" + NetProps.GetPropInt(s.ent,"m_Collision.m_nSolidType")
        + " damage=" + NetProps.GetPropInt(s.ent,"m_takedamage") + " pos=" + s.pos;
    P.Say(s.owner, text);
    P.Log("STATUS " + text);
};
P.Chat <- function(params)
{
    if (!("text" in params) || !("userid" in params)) return;
    local words = split(params.text.tolower(), " \t");
    if (words.len() == 0 || (words[0] != "!pet" && words[0] != "/pet")) return;
    P.Scan();
    if (!(params.userid in P.pets)) return;
    local s = P.pets[params.userid];
    if (Time() < s.nextCommand) return;
    s.nextCommand = Time() + 0.3;
    local cmd = words.len() > 1 ? words[1] : "help";
    if (cmd == "help") P.Say(s.owner, "E: pet | !pet come / stay / follow / dance / guide / status / off / on");
    else if (cmd == "status") P.Status(s);
    else if (cmd == "off") { s.disabled = true; P.Remove(s); P.Say(s.owner,"Pet hidden. Use !pet on to restore."); }
    else if (cmd == "on") { s.disabled = false; s.nextSpawn = 0.0; P.Say(s.owner,"Pet enabled; spawning in a safe nearby spot."); }
    else if (!P.Valid(s.ent)) P.Say(s.owner,"Pet not spawned yet. Try !pet on, then !pet status.");
    else if (cmd == "come")
    {
        if (Time() < s.nextRescue) P.Say(s.owner,"Recall cooling down; wait a moment.");
        else if (!P.Rescue(s,true)) P.Say(s.owner,"No safe nearby spawn spot. Move into an open area.");
    }
    else if (cmd == "stay" || cmd == "follow") { s.mode = cmd; s.route.clear(); P.Say(s.owner,"Mode: " + cmd); }
    else if (cmd == "dance" || cmd == "pet") P.Pet(s);
    else if (cmd == "guide") { if (Time() >= s.nextGuide) P.Guide(s,true); else P.Say(s.owner,"Route hint cooling down."); }
    else P.Say(s.owner,"Unknown command. Use !pet help.");
};
P.Error <- function(e)
{
    P.errors++;
    if (Time() >= P.nextError) { P.nextError = Time()+5.0; P.Log("ERROR: " + e); }
};
P.Tick <- function()
{
    local now = Time();
    local dt = now-P.lastTick;
    P.lastTick = now;
    if (dt < 0.0) dt = 0.0;
    if (dt > 0.15) dt = 0.15;
    P.ticks++;
    try { if (now >= P.nextScan) { P.nextScan = now+1.0; P.Scan(); } } catch(e) { P.Error(e); }
    foreach (id, s in P.pets)
        try { P.Update(s,dt); } catch(e) { P.Error("user=" + id + " " + e); }
    return P.Config.tick;
};
P.EnsureThink <- function()
{
    if (P.Valid(P.thinker)) return;
    local e = SpawnEntityFromTable("info_target", {targetname="trailpet_thinker"});
    if (!P.Valid(e)) throw "Could not create think entity";
    e.ValidateScriptScope();
    e.GetScriptScope()["TrailPetThink"] <- P.Tick;
    // ScriptMode_Init clears early director callbacks. The first engine think
    // runs after that synchronous initialization; register once, then use Tick.
    e.GetScriptScope()["TrailPetStart"] <- function()
    {
        __CollectEventCallbacks(P.events, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
        P.Log("EVENT CALLBACKS READY");
        AddThinkToEnt(e,"TrailPetThink");
        return P.Tick();
    };
    AddThinkToEnt(e,"TrailPetStart");
    P.thinker = e;
    P.lastTick = Time();
    P.nextScan = 0.0;
    P.Log("THINK READY");
};
P.Reset <- function()
{
    foreach(id,s in P.pets) P.Remove(s);
    P.pets.clear();
    P.finale = false;
    P.guidePausedUntil = 0.0;
    P.nextScan = 0.0;
    P.EnsureThink();
    P.Log("ROUND READY");
};
P.events.OnGameEvent_round_start_post_nav <- function(params) { try { P.Reset(); } catch(e) { P.Error(e); } };
P.events.OnGameEvent_player_spawn <- function(params) { try { P.EnsureThink(); P.nextScan=0.0; } catch(e) { P.Error(e); } };
P.events.OnGameEvent_player_say <- function(params) { try { P.Chat(params); } catch(e) { P.Error(e); } };
P.events.OnGameEvent_finale_start <- function(params) { P.finale = true; };
P.events.OnGameEvent_tank_spawn <- function(params) { P.guidePausedUntil = Time()+90.0; };
P.Log("SCRIPT LOADED; callbacks deferred to first engine think");
// Initial attempt plus round/player events cover early-load and later joins.
try { P.EnsureThink(); } catch(e) { P.Error(e); }
