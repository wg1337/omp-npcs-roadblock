#define MAX_PLAYERS (1000)
#define MAX_NPCS 150

#include <open.mp>
#include <GPS>
#include <YSI_Data/y_iterate.inc>

#define NPC_DESPAWN_RADIUS 500.0
#define NPC_SPAWN_SPACING 250.0
#define NPC_SPEED_MULTIPLIER 4

#define NPCNODETYPE_INVALID -1
#define NPCNODETYPE_STRAIGHT 0
#define NPCNODETYPE_LEFT 1
#define NPCNODETYPE_RIGHT 2

new Iterator:gNPCsPool<MAX_PLAYERS>;
new Iterator:gSpawnedPlayers<MAX_PLAYERS>;
new Iterator:gSpawnedNPCVehicles<MAX_VEHICLES>;

enum E_NPC_DATA {
    DespawnTimer,
    RemoveTimer,
    AimDelay,
    VehicleID,
    VehicleSlot,
    ActivePath,
    Float:VehicleOffset,
    Float:VehicleRoofSize,
    TraceID,
    bool:CalcInProgress,
    Name[MAX_PLAYER_NAME]
};
new gNPCsData[MAX_PLAYERS][E_NPC_DATA];

new gNPCVehicleOwner[MAX_VEHICLES];

enum E_PLAYER_DATA {
    TraceID,
    bool:CalcInProgress,
    SpawnTimer,
    MapNode:NPCPathNode[3],
    Path:NPCPathID[3],
    bool:IsNPCPathFinished[3]
};
new gPlayerData[MAX_PLAYERS][E_PLAYER_DATA];

stock GetRandomNPCName(name[], size) {
    static const firstNames[][] = {
        "Cadet",
        "Officer",
        "Corporal",
        "Sergeant",
        "Lieutenant",
        "Captain",
        "Commander",
        "Deputy",
        "Sheriff",
        "Chief"
    };

    static const lastNames[][] = {
        "Smith",
        "Johnson",
        "Williams",
        "Brown",
        "Jones",
        "Miller",
        "Davis",
        "Wilson",
        "Taylor",
        "Anderson",
        "Thomas",
        "Moore",
        "Martin",
        "Jackson",
        "White",
        "Harris",
        "Clark",
        "Lewis",
        "Walker",
        "Hall",
        "Allen",
        "Young",
        "King",
        "Wright",
        "Scott",
        "Green",
        "Baker",
        "Adams",
        "Nelson",
        "Hill",
        "Campbell",
        "Mitchell",
        "Roberts",
        "Carter",
        "Phillips",
        "Evans",
        "Turner",
        "Torres",
        "Parker",
        "Collins"
    };

    format(name, size, "%s_%s", firstNames[random(sizeof(firstNames))], lastNames[random(sizeof(lastNames))]);
}

bool:NPCNameExists(const name[]) {
    foreach(new i : gNPCsPool) {
        if(!NPC_IsValid(i))
            continue;

        if(!strcmp(gNPCsData[i][Name], name, true))
            return true;
    }
    return false;
}

stock GenerateNPCName(name[], size) {
    for(new i = 0; i<1000; i++) {
        GetRandomNPCName(name, size);
        if(!NPCNameExists(name)) {
            return true;
        }
    }
    return false;
}

stock bool:GetPositionInFrontOfVehicleWithAngleOffset(vehicleid, Float:distance, Float:angleOffset, &Float:x, &Float:y, &Float:z) {
    if(vehicleid == INVALID_VEHICLE_ID) {
        //printf("DEBUG: Could not use vehicle for position detection, vehicleid:%d", vehicleid);
        return false;
    }

    if(!GetVehiclePos(vehicleid, x, y, z)) {
        //printf("DEBUG: Could not get vehicle's position, vehicleid:%d", vehicleid);
        return false;
    }

    new Float:vx, Float:vy, Float:vz;

    if(GetVehicleVelocity(vehicleid, vx, vy, vz)) {
        new Float:speed = floatsqroot(vx * vx + vy * vy);

        if(speed > 0.01) {
            vx /= speed;
            vy /= speed;

            new Float:angle = atan2(-vx, vy) + angleOffset;
            x += floatsin(-angle, degrees) * distance;
            y += floatcos(-angle, degrees) * distance;

            return true;
        }
    }

    //Not moving, use angle only
    new Float:angle;
    if(!GetVehicleZAngle(vehicleid, angle)) {
        //printf("DEBUG: Could not get vehicle Z angle, vehicleid:%d", vehicleid);
        return false;
    }

    angle += angleOffset;
    x += floatsin(-angle, degrees) * distance;
    y += floatcos(-angle, degrees) * distance;

    return true;
}

main() {
    print("----------\nCop NPCs loaded.\n----------");
}

public OnFilterScriptInit() {

	print("+---------------------------------------------+");
	print("|  Loading Cops NPCs                          |");
	print("+---------------------------------------------+");

    CA_Init();

    Iter_Init(gNPCsPool);
    Iter_Init(gSpawnedPlayers);
    Iter_Init(gSpawnedNPCVehicles);

    foreach(new i : Player) {
        if(IsPlayerNPC(i)) continue;
        if(IsPlayerSpawned(i)) {
            Iter_Add(gSpawnedPlayers, i);
        }
    }

    for(new i = 0; i<MAX_PLAYERS; i++) {
        gNPCsData[i][VehicleID] = INVALID_VEHICLE_ID;
        gNPCsData[i][ActivePath] = INVALID_PATH_ID;
    }

    for(new i = 0; i<MAX_VEHICLES; i++) {
        gNPCVehicleOwner[i] = INVALID_NPC_ID;
    }

    LimitPlayerMarkerRadius(50.0);

    return true;
}

public OnFilterScriptExit() {
	print("+---------------------------------------------+");
	print("|  Unloading Cops NPCs                        |");
	print("+---------------------------------------------+");

    foreach(new i : gNPCsPool) {
        NPC_Destroy(i);
        Iter_Remove(gNPCsPool, i);
    }

    Iter_Clear(gSpawnedPlayers);

    foreach(new i : gSpawnedNPCVehicles) {
        DestroyVehicle(i);
        Iter_Remove(gSpawnedNPCVehicles, i);
    }
    
	return true;
}

stock InvalidateNPCPathCalc(playerid) {
    gPlayerData[playerid][CalcInProgress] = false;
    gPlayerData[playerid][TraceID]++;
    return true;
}

public OnPlayerSpawn(playerid) {
    if(IsPlayerNPC(playerid)) return true;
    if(gPlayerData[playerid][SpawnTimer] != INVALID_TIMER) {
        KillTimer(gPlayerData[playerid][SpawnTimer]);
    }
    gPlayerData[playerid][SpawnTimer] = SetTimerEx("FindNPCSpawnForPlayer", 2000, true, "i", playerid);
    Iter_Add(gSpawnedPlayers, playerid);

    return true;
}

public OnPlayerDeath(playerid, killerid, WEAPON:reason) {
    if(IsPlayerNPC(playerid)) return true;
    //printf("DEBUG: deathing... playerid:%d", playerid);
    if(gPlayerData[playerid][SpawnTimer] != INVALID_TIMER) {
        KillTimer(gPlayerData[playerid][SpawnTimer]);
        gPlayerData[playerid][SpawnTimer] = INVALID_TIMER;
    }
    InvalidateNPCPathCalc(playerid);
    Iter_Remove(gSpawnedPlayers, playerid);

    return true;
}

public OnPlayerDisconnect(playerid, reason) {
    if(IsPlayerNPC(playerid)) return true;
    //printf("DEBUG: diosonnecting... playerid:%d", playerid);
    
    if(gPlayerData[playerid][SpawnTimer] != INVALID_TIMER) {
        KillTimer(gPlayerData[playerid][SpawnTimer]);
        gPlayerData[playerid][SpawnTimer] = INVALID_TIMER;
    }
    InvalidateNPCPathCalc(playerid);
    Iter_Remove(gSpawnedPlayers, playerid);
    return true;
}

stock Float:GetVehicleSpeedMS(vehicleid) {
    new Float:vx, Float:vy, Float:vz;
    if(!GetVehicleVelocity(vehicleid, vx, vy, vz))
        return 0.0;

    return floatsqroot(vx * vx + vy * vy + vz * vz) * 50.0;
}

forward FindNPCSpawnForPlayer(playerid);
public FindNPCSpawnForPlayer(playerid) {

    if(GetPlayerWantedLevel(playerid) < 1) {
        //No point of checking nodes, only spawn when any wanted level is set
        return false;
    }

    //Early exit to prevent unneeded calculations
    if(Iter_Count(gNPCsPool) == MAX_NPCS) {
        printf("ERROR: No more free NPCs to use for spawning!");
        return false;
    }

    //This callback should only be called if player is spawned
    new vehicleid = GetPlayerVehicleID(playerid);
    if(vehicleid == INVALID_VEHICLE_ID) {
        //printf("DEBUG: Player should have been in a vehicle, playerid:%d", playerid);
        return false; //We only process spawns if player is driving
    }

    new PLAYER_STATE:state = GetPlayerState(playerid);
    if(state != PLAYER_STATE_DRIVER) {
        return false; //We only want to spawn cars for a driver
    }

    new Float:FrontX, Float:FrontY, Float:FrontZ;
    new Float:x, Float:y, Float:z;
    new MapNode:NodePlayer = INVALID_MAP_NODE_ID, MapNode:NodeStraight = INVALID_MAP_NODE_ID, MapNode:NodeLeft = INVALID_MAP_NODE_ID, MapNode:NodeRight = INVALID_MAP_NODE_ID;
    
    if(gPlayerData[playerid][CalcInProgress] == true) {
        //printf("DEBUG: Another NPC path calc thread is already running, playerid:%d", playerid);
        return false; //Something is still making calculations, don't start a new thread
    }
    if(!GetVehiclePos(vehicleid, x, y, z)) {
        //printf("DEBUG: Could not get vehicle pos, playerid:%d, vehicleid:%d", playerid, vehicleid);
        return false;
    }
    if(GetClosestMapNodeToPoint(x, y, z, NodePlayer) != GPS_ERROR_NONE) {
        //printf("DEBUG: Could not get player's closest node, playerid:%d", playerid);
        return false; //Get the player's node
    }
    if(NodePlayer == INVALID_MAP_NODE_ID) {
        //printf("DEBUG: Player does not seem to be close to any known node, playerid:%d", playerid);
        return false; //We need the player's node, cannot continue without it, but we can deal with other nodes missing
    }

    new Float:nodedistance = FLOAT_INFINITY;
    //Find how far is the node from the player, we don't want to spawn on too skewed nodes
    if(GetMapNodeDistanceFromPoint(NodePlayer, x, y, z, nodedistance) != GPS_ERROR_NONE) {
        printf("ERROR: Unable to get player's node distance, playerid:%d", playerid);
    }

    if(nodedistance > 300.0) {
        //printf("DEBUG: Player's node distance is out of range, probably going offorad, playerid:%d", playerid);
        return false;
    }

    new Float:SpawnDistance = 200.0 + GetVehicleSpeedMS(vehicleid) * NPC_SPEED_MULTIPLIER;

    if(!GetPositionInFrontOfVehicleWithAngleOffset(vehicleid, SpawnDistance, 0.0, FrontX, FrontY, FrontZ)) {
        //printf("DEBUG: Could not get position straight in front of player, playerid:%d", playerid);
        return false;
    }
    if(GetClosestMapNodeToPoint(FrontX, FrontY, FrontZ, NodeStraight) != GPS_ERROR_NONE) {
        //printf("DEBUG: Could not get a node in front of the player, playerid:%d", playerid);
        //We can deal with unable to find a node, continue
    }

    nodedistance = FLOAT_INFINITY;
    if(NodeStraight != INVALID_MAP_NODE_ID && GetMapNodeDistanceFromPoint(NodeStraight, x, y, z, nodedistance) != GPS_ERROR_NONE) {
        printf("ERROR: Unable to get straight node distance, playerid:%d", playerid);
    }

    if(nodedistance > NPC_DESPAWN_RADIUS) {
        //printf("DEBUG: Straight node distance is out of range, probably driving near water, playerid:%d", playerid);
        NodeStraight = INVALID_MAP_NODE_ID;
    }

    if(!GetPositionInFrontOfVehicleWithAngleOffset(vehicleid, SpawnDistance, -20.0, FrontX, FrontY, FrontZ)) {
        //printf("DEBUG: Could not get position left in front of player, playerid:%d", playerid);
        return false;
    }

    if(GetClosestMapNodeToPoint(FrontX, FrontY, FrontZ, NodeLeft) != GPS_ERROR_NONE) {
        //printf("DEBUG: Could not get a node left in front of the player, playerid:%d", playerid);
        //We can deal with unable to find a node, continue
    }

    nodedistance = FLOAT_INFINITY;
    if(NodeLeft != INVALID_MAP_NODE_ID && GetMapNodeDistanceFromPoint(NodeLeft, x, y, z, nodedistance) != GPS_ERROR_NONE) {
        printf("ERROR: Unable to get LEFT node distance, playerid:%d", playerid);
    }

    if(nodedistance > NPC_DESPAWN_RADIUS) {
        //printf("DEBUG: lEFT node distance is out of range, probably driving near water, playerid:%d", playerid);
        NodeLeft = INVALID_MAP_NODE_ID;
    }

    if(!GetPositionInFrontOfVehicleWithAngleOffset(vehicleid, SpawnDistance, 20.0, FrontX, FrontY, FrontZ)) {
        //printf("DEBUG: Could not get position right in front of player, playerid:%d", playerid);
        return false;
    }
    if(GetClosestMapNodeToPoint(FrontX, FrontY, FrontZ, NodeRight) != GPS_ERROR_NONE) {
        //printf("DEBUG: Could not get a node right in front of the player, playerid:%d", playerid);
        return false; //Get node to the right
    }

    nodedistance = FLOAT_INFINITY;
    if(NodeRight != INVALID_MAP_NODE_ID && GetMapNodeDistanceFromPoint(NodeRight, x, y, z, nodedistance) != GPS_ERROR_NONE) {
        printf("ERROR: Unable to get right node distance, playerid:%d", playerid);
    }

    if(nodedistance > NPC_DESPAWN_RADIUS) {
        //printf("DEBUG: Right node distance is out of range, probably driving near water, playerid:%d", playerid);
        NodeRight = INVALID_MAP_NODE_ID;
    }

    if(NodeStraight == INVALID_MAP_NODE_ID && NodeLeft == INVALID_MAP_NODE_ID && NodeRight == INVALID_MAP_NODE_ID) return false; //If we cannot get at least one node, then there is no point of calculating anything, just skip the task
    if(gPlayerData[playerid][TraceID] == cellmax) {
        printf("ERROR: This should have not ever happen, but a player's TraceID reached max, playerid:%d", playerid);
        Kick(playerid); //The player has been online for more than 32 years, they need to take a break
        //If you are reading this, then you should stop questioning the actual necessity of this check 
        return false;
    } 

    gPlayerData[playerid][CalcInProgress] = true; //Lock to prevent new threads from starting
    gPlayerData[playerid][TraceID]++;
    gPlayerData[playerid][NPCPathID][NPCNODETYPE_STRAIGHT] = INVALID_GPS_PATH_ID;
    gPlayerData[playerid][NPCPathNode][NPCNODETYPE_STRAIGHT] = NodeStraight;
    if(NodeStraight == INVALID_MAP_NODE_ID) {
        gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_STRAIGHT] = true; //Node was not found, no point of calculating path
    } else {
        gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_STRAIGHT] = false;
        if(FindPathThreaded(NodePlayer, NodeStraight, "OnBestPathFromNodeToPlayerFound", "iiiii", playerid, gPlayerData[playerid][TraceID], NPCNODETYPE_STRAIGHT, _:NodePlayer, _:NodeStraight)) {
            //Mark path calculation as done and hope other paths are getting calculated
            gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_STRAIGHT] = true;
        }
    }
    gPlayerData[playerid][NPCPathID][NPCNODETYPE_LEFT] = INVALID_GPS_PATH_ID;
    gPlayerData[playerid][NPCPathNode][NPCNODETYPE_LEFT] = NodeLeft;
    if(NodeLeft == INVALID_MAP_NODE_ID) {
        gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_LEFT] = true; //Node was not found, no point of calculating path
    } else {
        gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_LEFT] = false;
        if(FindPathThreaded(NodePlayer, NodeLeft, "OnBestPathFromNodeToPlayerFound", "iiiii", playerid, gPlayerData[playerid][TraceID], NPCNODETYPE_LEFT, _:NodePlayer, _:NodeLeft)) {
            //Mark path calculation as done and hope other paths are getting calculated
            gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_LEFT] = true;
        }
    }
    gPlayerData[playerid][NPCPathID][NPCNODETYPE_RIGHT] = INVALID_GPS_PATH_ID;
    gPlayerData[playerid][NPCPathNode][NPCNODETYPE_RIGHT] = NodeRight;
    if(NodeRight == INVALID_MAP_NODE_ID) {
        gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_RIGHT] = true; //Node was not found, no point of calculating path
    } else {
        gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_RIGHT] = false;
        if(FindPathThreaded(NodePlayer, NodeRight, "OnBestPathFromNodeToPlayerFound", "iiiii", playerid, gPlayerData[playerid][TraceID], NPCNODETYPE_RIGHT, _:NodePlayer, _:NodeRight)) {
            //Mark path calculation as done and hope other paths are getting calculated
            gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_RIGHT] = true;
        }
    }

    return true;
}

stock Float:GetNPCDistanceToPoint(npcid, Float:x, Float:y, Float:z) {
    new Float:NPCX, Float:NPCY, Float:NPCZ;
    new npcvehicleid = NPC_GetVehicleID(npcid);
    if(npcvehicleid != INVALID_VEHICLE_ID) {
        if(!GetVehiclePos(npcvehicleid, NPCX, NPCY, NPCZ)) {
            printf("ERROR: Unable to get NPCs vehicle pos, npcid:%d, npcvehicleid:%d", npcid, npcvehicleid);
            return FLOAT_INFINITY;
        }
    } else {
        if(!NPC_GetPos(npcid, NPCX, NPCY, NPCZ)) {
            printf("ERROR: Unable to get NPCs pos, npcid:%d", npcid);
            return FLOAT_INFINITY;
        }
    }
    return floatsqroot((NPCX - x) * (NPCX - x) + (NPCY - y) * (NPCY - y) + (NPCZ - z) * (NPCZ - z));
}

stock bool:GetNPCSpawnLevelAttributes(wantedlevel, &skin, &carmodel, &WEAPON:weapon, &delay, &Float:vehicleoffset) {

    switch(wantedlevel) {
        case 0: {
            //At wanted level 0 do nothing, don't spawn
            return false;
        }
        case 1: {
            static const skins[] = {
                284,
                306,
                282,
                281,
                283,
                266
            };

            static const vehicles[] = {
                523,
                596,
                597,
                598
            };

            static const WEAPON:weapons[] = {
                WEAPON_COLT45
            };

            skin = skins[random(sizeof(skins))];
            carmodel = vehicles[random(sizeof(vehicles))];
            weapon = weapons[random(sizeof(weapons))];
            delay = 1500;
            vehicleoffset = 0.0;


        }
        case 2: {
            static const skins[] = {
                311,
                280,
                301,
                309,
                265,
                304,
                310
            };

            static const vehicles[] = {
                596,
                597,
                598
            };

            static const WEAPON:weapons[] = {
                WEAPON_DEAGLE,
                WEAPON_SHOTGUN
            };

            skin = skins[random(sizeof(skins))];
            carmodel = vehicles[random(sizeof(vehicles))];
            weapon = weapons[random(sizeof(weapons))];
            delay = 1000;
            vehicleoffset = 3.0;

        }
        case 3: {
            static const skins[] = {
                302,
                288,
                267,
                303,
                305,
                285
            };

            static const vehicles[] = {
                599,
                596,
                597,
                598
            };

            static const WEAPON:weapons[] = {
                WEAPON_UZI,
                WEAPON_DEAGLE
            };

            skin = skins[random(sizeof(skins))];
            carmodel = vehicles[random(sizeof(vehicles))];
            weapon = weapons[random(sizeof(weapons))];
            delay = 800;
            vehicleoffset = 3.0;

        }
        case 4: { //Swat
            static const skins[] = {
                307
            };

            static const vehicles[] = {
                601,
                427
            };

            static const WEAPON:weapons[] = {
                WEAPON_UZI,
                WEAPON_TEC9
            };

            skin = skins[random(sizeof(skins))];
            carmodel = vehicles[random(sizeof(vehicles))];
            weapon = weapons[random(sizeof(weapons))];
            delay = 700;
            vehicleoffset = 3.0;
 
        }
        case 5: { //FBI
            static const skins[] = {
                286
            };

            static const vehicles[] = {
                490,
                528
            };

            static const WEAPON:weapons[] = {
                WEAPON_MP5,
                WEAPON_SHOTGSPA
            };

            skin = skins[random(sizeof(skins))];
            carmodel = vehicles[random(sizeof(vehicles))];
            weapon = weapons[random(sizeof(weapons))];
            delay = 600;
            vehicleoffset = 3.0;

        }
        case 6: { //Army
            static const skins[] = {
                287
            };

            static const vehicles[] = {
                433
            };

            static const WEAPON:weapons[] = {
                WEAPON_ROCKETLAUNCHER,
                WEAPON_M4
            };

            skin = skins[random(sizeof(skins))];
            carmodel = vehicles[random(sizeof(vehicles))];
            weapon = weapons[random(sizeof(weapons))];
            delay = 200;
            vehicleoffset = 4.5;

        }
        default: {
            return false;
        }
    }

    return true;
}

stock SpawnNPCsForPlayerAtPos(playerid, Float:x, Float:y, Float:z, Path:pathid, size, vehicleslot, wantedlevel) {
    new skin, carmodel, WEAPON:weapon, shootdelay, Float:vehicleoffset;
    if(!GetNPCSpawnLevelAttributes(wantedlevel, skin, carmodel, weapon, shootdelay, vehicleoffset)) {
        //Probably not a proper wanted level, skip spawning
        return false;
    }

    new npcid = CreateNPCWithName();
    if(npcid == INVALID_NPC_ID) {
        printf("ERROR: Unable to create a new NPC for spawn");
        return false;
    }

    gNPCsData[npcid][DespawnTimer] = SetTimerEx("CheckNPCDespawnRadius", 2000, true, "i", npcid);
   
    Iter_Add(gNPCsPool, npcid);
    gNPCsData[npcid][DespawnTimer] = INVALID_TIMER;
    gNPCsData[npcid][RemoveTimer] = INVALID_TIMER;
    NPC_Spawn(npcid);
    NPC_SetInvulnerable(npcid, false);
    NPC_SetArmour(npcid, 100.0);
    NPC_SetPos(npcid, x, y, z+1);
    
    SetPlayerColor(npcid, 0xFFFFFF00); //Hide NPCs a bit

    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_PISTOL, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_DESERT_EAGLE, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_SHOTGUN, 999);

    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_SNIPERRIFLE, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_M4, 999);

    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_MP5, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_SPAS12_SHOTGUN, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_MICRO_UZI, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_MP5, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_MICRO_UZI, 999);
    NPC_SetWeaponSkillLevel(npcid, WEAPONSKILL_DESERT_EAGLE, 999);

    NPC_SetWeapon(npcid, weapon);
    NPC_SetSkin(npcid, skin);
    NPC_SetAmmo(npcid, 999);
    NPC_EnableInfiniteAmmo(npcid, true);

    gNPCsData[npcid][VehicleSlot] = vehicleslot;
    gNPCsData[npcid][AimDelay] = shootdelay;
    gNPCsData[npcid][VehicleOffset] = vehicleoffset;
    

    new Float:sizex, Float:sizey, Float:sizez;
    GetVehicleModelInfo(carmodel, VEHICLE_MODEL_INFO_SIZE, sizex, sizey, sizez);
    gNPCsData[npcid][VehicleRoofSize] = sizez;


    new bool:NPConfoot = false;FindNPCSpawnForPlayer
    new vehicleid = CreateVehicle(carmodel, x, y, z+1, 0, -1, -1, -1, true);
    if(vehicleid != INVALID_VEHICLE_ID) {
        Iter_Add(gSpawnedNPCVehicles, vehicleid);
        SetVehicleParamsEx(vehicleid, VEHICLE_PARAMS_ON, VEHICLE_PARAMS_ON, VEHICLE_PARAMS_OFF, VEHICLE_PARAMS_ON, VEHICLE_PARAMS_OFF, VEHICLE_PARAMS_OFF, VEHICLE_PARAMS_OFF); 
        if(!NPC_PutInVehicle(npcid, vehicleid, 0)) {
            NPConfoot = true;
            printf("ERROR: Unable to put NPC in vehicle, npcid:%d, vehicleid:%d", npcid, vehicleid);

            //We were not able to put the NPC in a vehicle, so just make the NPC hostile on foot
            SetTimerEx("MakeNPCHostileToPlayer", 200, false, "iii", npcid, playerid, gNPCsData[npcid][AimDelay]);
        } else {
            if(!NPC_UseVehicleSiren(npcid, true)) {
                printf("ERROR: Unable to use siren for NPC vehicle, npcid:%d, vehicleid:%d", npcid, vehicleid);
            }
        }
        gNPCsData[npcid][VehicleID] = vehicleid;
        gNPCVehicleOwner[vehicleid] = npcid;

    } else {
        NPConfoot = true;
        //We were not able to put the NPC in a vehicle, so just make the NPC hostile on foot
        SetTimerEx("MakeNPCHostileToPlayer", 200, false, "iii", npcid, playerid, gNPCsData[npcid][AimDelay]);
    }

    gNPCsData[npcid][ActivePath] = NPC_CreatePath();


    new MapNode:nodeid, Float:pathx, Float:pathy, Float:pathz;
    for (new index = size-1; index >= 0; index--) { //Drive in reverse, puts NPCs on the correct lane
        
        if(GetPathNode(pathid, index, nodeid) == GPS_ERROR_NONE) {
            if(GetMapNodePos(nodeid, pathx, pathy, pathz) == GPS_ERROR_NONE) {
                if(!NPC_AddPointToPath(gNPCsData[npcid][ActivePath], pathx, pathy, pathz+1, 1.5)) {
                    printf("ERROR: Unable to add point to NPC path, npcid:%d", npcid);
                }
            } else {
                printf("ERROR: Unable to get node position for NPC, npcid:%d", npcid);
            }
        } else {
            printf("ERROR: Unable to get node path for NPC, npcid:%d", npcid);
        }
    }

    if(NPConfoot == true) {
        NPC_MoveByPath(npcid, gNPCsData[npcid][ActivePath], NPC_MOVE_TYPE_JOG, 2.0);
    } else {
        NPC_MoveByPath(npcid, gNPCsData[npcid][ActivePath], NPC_MOVE_TYPE_DRIVE, 2.0);
    }


    return true;
}

forward MakeNPCHostileToPlayer(npcid, playerid, delay);
public MakeNPCHostileToPlayer(npcid, playerid, delay) {
    if(GetPlayerVehicleID(playerid) != INVALID_VEHICLE_ID) {
        //Randomly pick shooting target
        static const Float:ShootOffsets[] = {
            0.0, //Chasis
            -0.5, //idk, random
            -1.0 //Tires
        };

        new Float:NPCShootOffset = ShootOffsets[random(sizeof(ShootOffsets))];
        NPC_AimAtPlayer(npcid, playerid, true, delay, true, 0.0, 0.0, NPCShootOffset, 0.0, 0.0, 0.6, NPC_ENTITY_CHECK_PLAYER);
    } else {
        NPC_AimAtPlayer(npcid, playerid, true, delay, true, 0.0, 0.0, 0.2, 0.0, 0.0, 0.6, NPC_ENTITY_CHECK_PLAYER);
    }
}

stock SpawnNPCInFrontOfPlayer(playerid, nodetype) {
    if(gPlayerData[playerid][NPCPathID][nodetype] == INVALID_GPS_PATH_ID) {
        printf("ERROR: Player's best path for NPC path is invalid, playerid:%d", playerid);
        return false;
    }

    new size;
    if(GetPathSize(gPlayerData[playerid][NPCPathID][nodetype], size) == GPS_ERROR_INVALID_PATH) {
        printf("ERROR: Player's best path does not have a valid path size, playerid:%d", playerid);
        return false;
    }

    new MapNode:nodeid;
    if(GetPathNode(gPlayerData[playerid][NPCPathID][nodetype], size-1, nodeid) != GPS_ERROR_NONE) { //Get the last node's location, NPCs spawn location
        printf("ERROR: Player's best path does not have a valid nodeid, playerid:%d, pathid:%d", playerid, _:gPlayerData[playerid][NPCPathID][nodetype]);
        return false;
    }

    new Float:x, Float:y, Float:z;
    if(GetMapNodePos(nodeid, x, y, z) == GPS_ERROR_INVALID_NODE) {
        printf("ERROR: Could not get nodeid's position, playerid:%d, nodeid:%d", playerid, _:nodeid);
        return false;
    }

    foreach(new i : gNPCsPool) {
        if(GetNPCDistanceToPoint(i, x, y, z) < NPC_SPAWN_SPACING) {
            //Somebody is already spawned in the radius, don't spawn new ones
            return false;
        }
    }

    new wantedlevel = GetPlayerWantedLevel(playerid);
    if(wantedlevel < 2) {
        SpawnNPCsForPlayerAtPos(playerid, x, y, z, gPlayerData[playerid][NPCPathID][nodetype], size, 2, wantedlevel);
    } else {
        SpawnNPCsForPlayerAtPos(playerid, x, y, z, gPlayerData[playerid][NPCPathID][nodetype], size, 1, wantedlevel);
        SpawnNPCsForPlayerAtPos(playerid, x, y, z, gPlayerData[playerid][NPCPathID][nodetype], size, 0, wantedlevel);
    }

    return true;
}

forward public OnBestPathFromNodeToPlayerFound(Path:pathid, playerid, traceid, nodetype, MapNode:NodePlayer, MapNode:TargetNode);
public OnBestPathFromNodeToPlayerFound(Path:pathid, playerid, traceid, nodetype, MapNode:NodePlayer, MapNode:TargetNode) {
    if(!IsPlayerConnected(playerid)) {
        //Player simply disconnected, no point of calculating anything
        //printf("DEBUG: Player disconnected during NPC path calc Trace ID:%d, playerid:%d", traceid, playerid);
        return false;
    }

    if(gPlayerData[playerid][SpawnTimer] == INVALID_TIMER || gPlayerData[playerid][TraceID] != traceid || gPlayerData[playerid][CalcInProgress] == false) {
        //Something has stopped NPC spawning, lets invalidate further calculations too
        //printf("DEBUG: Something has stopped NPC path calc for Trace ID:%d, playerid:%d", traceid, playerid);
        return false; 
    } 

    gPlayerData[playerid][IsNPCPathFinished][nodetype] = true;
    gPlayerData[playerid][NPCPathID][nodetype] = pathid;

    if(gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_STRAIGHT] != true || gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_LEFT] != true || gPlayerData[playerid][IsNPCPathFinished][NPCNODETYPE_RIGHT] != true) {
        //All threads have not yet finished, so we skip from here
        //printf("DEBUG: Waiting for other NPC path calc threads to finish for Trace ID:%d, playerid:%d", traceid, playerid);
        return false;
    }
    gPlayerData[playerid][CalcInProgress] = false; //Unlock threads for new calculations

    //Get all paths lengths, ignore failures
    new Float:LengthStraight = FLOAT_INFINITY, Float:LengthLeft = FLOAT_INFINITY, Float:LengthRight = FLOAT_INFINITY;
    if(IsValidPath(gPlayerData[playerid][NPCPathID][NPCNODETYPE_STRAIGHT]))
        GetPathLength(gPlayerData[playerid][NPCPathID][NPCNODETYPE_STRAIGHT], LengthStraight);
    if(IsValidPath(gPlayerData[playerid][NPCPathID][NPCNODETYPE_LEFT]))
        GetPathLength(gPlayerData[playerid][NPCPathID][NPCNODETYPE_LEFT], LengthLeft);
    if(IsValidPath(gPlayerData[playerid][NPCPathID][NPCNODETYPE_RIGHT]))
        GetPathLength(gPlayerData[playerid][NPCPathID][NPCNODETYPE_RIGHT], LengthRight);

    new Float:BestLength = FLOAT_INFINITY;
    new BestNodeType = NPCNODETYPE_INVALID;

    if(LengthStraight < BestLength) {
        BestLength = LengthStraight;
        BestNodeType = NPCNODETYPE_STRAIGHT;
    }

    if(LengthLeft < BestLength) {
        BestLength = LengthLeft;
        BestNodeType = NPCNODETYPE_LEFT;
    }

    if(LengthRight < BestLength) {
        BestLength = LengthRight;
        BestNodeType = NPCNODETYPE_RIGHT;
    }

    if (BestNodeType == NPCNODETYPE_INVALID) {
        //No valid path was found
        return false;
    }
    #pragma unused BestLength

    SpawnNPCInFrontOfPlayer(playerid, BestNodeType);

    return true;
}

stock CreateNPCWithName() {
    if(Iter_Count(gNPCsPool) == MAX_NPCS) {
        printf("ERROR: No more free NPCs to use for spawning!");
        return INVALID_NPC_ID;
    }

    new name[MAX_PLAYER_NAME];
    if(!GenerateNPCName(name, MAX_PLAYER_NAME)) {
        printf("ERROR: Failed to generate NPC name!");
        return INVALID_NPC_ID;
    }
    new npcid = NPC_Create(name);
    if(npcid == INVALID_NPC_ID) {
        printf("ERROR: Failed to create a new NPC (ID: %d, name: %s)!", npcid, name);
        return INVALID_NPC_ID;
    }
    
    //Add NPC name to global array
    format(gNPCsData[npcid][Name], MAX_PLAYER_NAME, "%s", name);
    return npcid;
}



public OnNPCCreate(npcid) {

    return true;
}

public OnNPCDestroy(npcid) {

    return true;
}

public OnNPCSpawn(npcid) {

    return true;
}

stock Float:GetPlayerDistanceToNPC(playerid, npcid) {
    new Float:NPCX, Float:NPCY, Float:NPCZ;
    new npcvehicleid = NPC_GetVehicleID(npcid);

    if(npcvehicleid != INVALID_VEHICLE_ID) {
        if(!GetVehiclePos(npcvehicleid, NPCX, NPCY, NPCZ))
            return FLOAT_INFINITY;
    } else {
        if(!NPC_GetPos(npcid, NPCX, NPCY, NPCZ))
            return FLOAT_INFINITY;
    }

    new playervehicleid = GetPlayerVehicleID(playerid);

    if(playervehicleid != INVALID_VEHICLE_ID)
        return GetVehicleDistanceFromPoint(playervehicleid, NPCX, NPCY, NPCZ);

    return GetPlayerDistanceFromPoint(playerid, NPCX, NPCY, NPCZ);
}

forward CheckNPCDespawnRadius(npcid);
public CheckNPCDespawnRadius(npcid) {
    new Float:NearestDistance = FLOAT_INFINITY;
    new NearestPlayerID = INVALID_PLAYER_ID;
    foreach(new i : gSpawnedPlayers) {
        new Float:distance = GetPlayerDistanceToNPC(i, npcid);
        if(distance > NPC_DESPAWN_RADIUS) {
            //Player is way outside the despawn radius
            //printf("DEBUG: Depsawning NPC because large radius, npcid:%d, distance:%f", npcid, distance);
            continue;
        }
        if(distance < NearestDistance) {
            NearestDistance = distance;
            NearestPlayerID = i;
        }
    }

    if(NearestPlayerID != INVALID_PLAYER_ID) {
        //Somebody is near, cannot despawn yet
        //Just set the nearest player as the target
        //printf("DEBUG: Targeting new player, playerid:%d, distance:%f", NearestPlayerID,  NearestDistance);
        MakeNPCHostileToPlayer(npcid, NearestPlayerID, gNPCsData[npcid][AimDelay]);
        return false;
    }

    DespawnNPC(npcid);
    return true;
}

stock DespawnNPC(npcid) {
    if(gNPCsData[npcid][DespawnTimer] != INVALID_TIMER) {
        KillTimer(gNPCsData[npcid][DespawnTimer]);
        gNPCsData[npcid][DespawnTimer] = INVALID_TIMER;
    }
    if(gNPCsData[npcid][RemoveTimer] != INVALID_TIMER) {
        KillTimer(gNPCsData[npcid][RemoveTimer]);
        gNPCsData[npcid][RemoveTimer] = INVALID_TIMER;
    }
    gNPCsData[npcid][ActivePath] = INVALID_PATH_ID;
    //NPC_ResetSurfingData(npcid); //Prevents a NPC from surfing newly created vehicles, maybe

    //Destroy the vehicle if the NPC dies. it is simpler
    if(gNPCsData[npcid][VehicleID] != INVALID_VEHICLE_ID) {
        Iter_Remove(gSpawnedNPCVehicles, gNPCsData[npcid][VehicleID]);
        DestroyVehicle(gNPCsData[npcid][VehicleID]);
        gNPCVehicleOwner[gNPCsData[npcid][VehicleID]] = INVALID_NPC_ID;
        gNPCsData[npcid][VehicleID] = INVALID_VEHICLE_ID;
    }

    gNPCsData[npcid][Name][0] = '\0';
    Iter_Remove(gNPCsPool, npcid);

    NPC_Destroy(npcid);
}

public OnNPCDeath(npcid, killerid, WEAPON:reason) {
    if(Iter_Contains(gNPCsPool, npcid)) {
        DespawnNPC(npcid);
    }
    return true;
}

public OnVehicleDeath(vehicleid, killerid) {
    if(gNPCVehicleOwner[vehicleid] != INVALID_NPC_ID) {
        //We don't want to respawn npc vehicles
        DestroyVehicle(vehicleid);
        Iter_Remove(gSpawnedNPCVehicles, vehicleid);
        gNPCsData[gNPCVehicleOwner[vehicleid]][VehicleID] = INVALID_VEHICLE_ID;
    }
    return true;
}

new gPlayerVeh = INVALID_VEHICLE_ID;
public OnPlayerCommandText(playerid, cmdtext[]) {

    if (strcmp(cmdtext, "/wanted", true, 7) == 0)
    {
        new wantedlevel = strval(cmdtext[8]);

        SetPlayerWantedLevel(playerid, wantedlevel);
        return 1;
    }

    if (!strcmp(cmdtext, "/car", true)) {
        if(IsValidVehicle(gPlayerVeh)) {
            DestroyVehicle(gPlayerVeh);
        }
        new Float:x, Float:y, Float:z;
        GetPlayerPos(playerid, x, y, z);
        gPlayerVeh = CreateVehicle(419, x, y+3, z+1, 82.2873, -1, -1, 60);
        PutPlayerInVehicle(playerid, gPlayerVeh, 0);
        return true;
    }

    if (!strcmp(cmdtext, "/findpaths", true)) {
        gPlayerData[playerid][SpawnTimer] = SetTimerEx("FindNPCSpawnForPlayer", 2000, true, "i", playerid);
        return true;
    }

    if (!strcmp(cmdtext, "/weapon", true)) {
        GivePlayerWeapon(playerid, WEAPON_SAWEDOFF, 64); // Give playerid a sawn-off shotgun with 64 ammo
        return true;
    }

    return false;
}

stock bool:TurnVehiclePerpendicular(vehicleid) {
    if(vehicleid == INVALID_VEHICLE_ID) return false;
    new Float:angle;
    if(!GetVehicleZAngle(vehicleid, angle)) return false;
    angle += 90.0;
    if(angle >= 360.0) angle -= 360.0;
    return SetVehicleZAngle(vehicleid, angle);
}

stock bool:CheckNPCDistanceToPlayers(npcid, pathid) {
    new Float:shortestdistance = FLOAT_INFINITY;
    foreach(new i : gSpawnedPlayers) {
        new Float:distance = GetPlayerDistanceToNPC(i, npcid);
        if(distance < shortestdistance) {
            shortestdistance = distance;
        }
        if(distance < 40) {
            break; //If player is very close, then no point of finding other players, we need to stop right now to prevent a random road block appearing too close to the player
        }
    }

    if(shortestdistance < 150.0) {
        if(!NPC_StopMove(npcid)) {
            printf("ERROR: Unable to stop NPC moving, npcid:%d", npcid);
        }
        if(!NPC_SetVelocity(npcid, 0, 0, 0)) {
            printf("ERROR: Unable to set velocity for NPC, npcid:%d", npcid);
        }
        if(!NPC_DestroyPath(pathid)) {
            printf("ERROR: Unable to destroy move path for NPC, npcid:%d", npcid);
        }
        if(gNPCsData[npcid][RemoveTimer] != INVALID_TIMER) {
            KillTimer(gNPCsData[npcid][RemoveTimer]);
        }
        gNPCsData[npcid][RemoveTimer] = SetTimerEx("RemoveNPCFromDrivingVehicle", 500, false, "df", npcid, shortestdistance);
        gNPCsData[npcid][ActivePath] = INVALID_PATH_ID;
    }
    return true;
}

public OnNPCFinishMovePathPoint(npcid, pathid, pointid) {
    if(Iter_Contains(gNPCsPool, npcid)) {
        CheckNPCDistanceToPlayers(npcid, pathid);
    }
    return true;
}

stock bool:SetupNPCRoadblockVehicle(vehicleid, slot, Float:sideOffset, &Float:x, &Float:y, &Float:z) {
    if(vehicleid == INVALID_VEHICLE_ID) return false;
    new Float:angle;
    if(!GetVehiclePos(vehicleid, x, y, z)) return false;
    if(!GetVehicleZAngle(vehicleid, angle)) return false;

    // Direction perpendicular to the road.
    new Float:sideAngle = angle + 90.0;

    if(sideAngle >= 360.0) sideAngle -= 360.0;

    // Default: car faces perpendicular to the road.
    new Float:facingAngle = sideAngle;

    if(slot == 0) {
        // Left side.
        sideOffset = -sideOffset;
    } else if(slot == 1) {
        // Right side.
        // Keep the position offset positive,
        // but make the car face the opposite direction.
        facingAngle += 180.0;

        if(facingAngle >= 360.0) facingAngle -= 360.0;
    } else if(slot == 2) {
        // Center.
        sideOffset = 0.0;
    }

    // Position using sideAngle, NOT facingAngle.
    x += floatsin(-sideAngle, degrees) * sideOffset;
    y += floatcos(-sideAngle, degrees) * sideOffset;

    if(!SetVehiclePos(vehicleid, x, y, z)) return false;
    if(!SetVehicleZAngle(vehicleid, facingAngle)) return false;

    return true;
}

forward RemoveNPCFromDrivingVehicle(npcid, Float:distance);
public RemoveNPCFromDrivingVehicle(npcid, Float:distance) {
    gNPCsData[npcid][RemoveTimer] = INVALID_TIMER;
    new vehicleid = NPC_GetVehicleID(npcid);
    if(vehicleid != INVALID_VEHICLE_ID) {
        new Float:x, Float:y, Float:z;
        if(distance > 40.0) { //Don't set up a roadblock if player is too near
            if(!SetupNPCRoadblockVehicle(vehicleid, gNPCsData[npcid][VehicleSlot], gNPCsData[npcid][VehicleOffset], x, y, z)) {
                printf("ERROR: Unable to turn NPC vehicle perpendicular, npcid:%d vehicleid:%d", npcid, vehicleid);
                GetVehiclePos(vehicleid, x, y, z); //last effort
            }
        }
        if(!NPC_RemoveFromVehicle(npcid)) {
            printf("ERROR: Unable to remove NPC from vehicle, npcid:%d", npcid);
        }
        new Float:zoffset = gNPCsData[npcid][VehicleRoofSize] ;
        //printf("DEBUG: Roof offset is %f", gNPCsData[npcid][VehicleRoofSize]);
        if(gNPCsData[npcid][VehicleRoofSize] > 4.0) {
            zoffset = gNPCsData[npcid][VehicleRoofSize] - 2;
        }
        NPC_Move(npcid, x, y, z+zoffset, NPC_MOVE_TYPE_JOG, NPC_MOVE_SPEED_AUTO, 0.2);
        NPC_SetSurfingVehicle(npcid, vehicleid); //Prevent floating NPCs
        NPC_SetSurfingOffsets(npcid, 0, 0, zoffset);
    }
}
