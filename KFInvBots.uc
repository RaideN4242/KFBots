// Written by Marco
Class KFInvBots extends KFInvasionBot;

// #ifdef WITH_AMMO_BOX
	// #exec obj load file="KFBox.u"
// 
	 var AmmoBox SeekingAmmo;
	 var float NextAmmoCheckTime;
// #endif

// #ifdef WITH_SENTRY_BOT
	 var SentryGun MySentryGun;
// #endif

struct FWeldedPath
{
	var KFDoorMover Door;
	var ReachSpec Path;
};
var array<FWeldedPath> DoorPaths;
var float NextTargetCheck,NextKnifeTime,NextMedicFireTime,NextNadeTimer,NextPipebombTimer,NextAssistTimer,NextGroupTimer,BotSupportTimer,WeldAssistTimer;
var KFBotsMut Mute;
var byte HealState,OldMovesCount;
var float RetreatTime,LastEnemyEncounter;
var NavigationPoint CurrentMov,OldMoves[4],PreviousNavPath,LastBestGroup;
var array<NavigationPoint> TempBlockedPaths;
var KFWeapon MyMedGun;
var KFInvBots BeggingTarget,AnswerBegger;
var PlayerController DonatePlayer;
var Controller AssistingPlayer;
var KFBotUseTrigger UseNotify;
var Pawn FollowingPawn,BotSupportActor;
var RosterEntry UsingRooster;
var Actor ShopVolumeActor;
var Frag MyGrenades;
var PipeBombExplosive MyPipes;
var byte Personality,AssistWeldMode;

var vector GuardingPosition;
var bool bGuardPosition,bWallAdjust;

// #ifdef WITH_AMMO_BOX
	 var bool bHighPriorityAmmo,bWantedAmmo,bAmmoBoxInUse;
// #endif

// #if DEBUG_MODE
	// #pragma ucpp warning Debug mode enabled!
	// #define DEBUGF(Msg) DebugMsg(Msg,__LINE__)
	// final function DebugMsg( string Msg, int Line )
	// {
		// Level.GetLocalPlayerController().ClientMessage(Msg);
		// Log(Msg$", Line: "$Line,'BotDebug');
	// }
// #else
	// #define DEBUGF(Msg) // debugf
// #endif

function AssignPersonality()
{
	// Randomize personality.
	Accuracy = FRand();
	BaseAggressiveness = FRand();
	StrafingAbility = -1 + FRand()*2.f;
	CombatStyle = -1 + FRand()*2.f;
	Tactics = FRand();
	ReactionTime = FRand();
	Jumpiness = FRand();
	Personality = Rand(3);
	FollowingPawn = None;
}
function PostBeginPlay()
{
	Super.PostBeginPlay();
	UseNotify = Spawn(Class'KFBotUseTrigger',Self);
	AssignPersonality();
}
function Destroyed()
{
	if( UseNotify!=None )
		UseNotify.Destroy();
	if( UsingRooster!=None )
		UsingRooster.bTaken = false;
	Super.Destroyed();
}

function NotifyAddInventory(inventory NewItem)
{
	local byte i;
	local KFMeleeFire F;

	Super.NotifyAddInventory(NewItem);
	
	// HACK: Give extra melee range.
	if( KFWeapon(NewItem)!=None && KFWeapon(NewItem).bMeleeWeapon )
	{
		for( i=0; i<2; ++i )
		{
			F = KFMeleeFire(Weapon(NewItem).GetFireMode(i));
			if( F!=None )
				F.WeaponRange = F.Default.WeaponRange * 2.f;
		}
	}
	if( Syringe(NewItem)!=none )
		MySyringe = Syringe(NewItem);
	else if( Frag(NewItem)!=None )
		MyGrenades = Frag(NewItem);
	else if( PipeBombExplosive(NewItem)!=None )
		MyPipes = PipeBombExplosive(NewItem);
// #ifdef WITH_SENTRY_BOT
	 else if( SentryGun(NewItem)!=None )
		 MySentryGun = SentryGun(NewItem);
// #endif
	else if( Welder(NewItem)!=None )
		ActiveWelder = Welder(NewItem);
}

final function Actor GetRandomDest()
{
	local int i;
	local Actor Result;
	
	// Setup special path finding.
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = true;
	for( i=0; i<DoorPaths.Length; ++i )
	{
		if( DoorPaths[i].Door.bSealed && !DoorPaths[i].Door.bDoorIsDead )
			DoorPaths[i].Path.CollisionRadius -= 10000; // Pretend that no pawn is small enough to use this.
		else DoorPaths.Remove(i--,1); // Remove opened paths.
	}

	Result = FindRandomDest();
	if( Result!=None )
	{
		PreviousNavPath = NavigationPoint(RouteCache[0]);
		if( PreviousNavPath!=None && PreviousNavPath.bBlocked ) // Shouldn't be possible, but just in case.
			PreviousNavPath = None;
	}

	// Un-setup path finding.
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = false;
	for( i=0; i<DoorPaths.Length; ++i )
		DoorPaths[i].Path.CollisionRadius += 10000;

	return Result;
}
function bool FindBestPathToward(Actor A, bool bCheckedReach, bool bAllowDetour)
{
	local int i;

	if ( !bCheckedReach && ActorReachable(A) )
	{
		MoveTarget = A;
		return true;
	}

	// Setup special path finding.
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = true;
	for( i=0; i<DoorPaths.Length; ++i )
	{
		if( DoorPaths[i].Door.bSealed && !DoorPaths[i].Door.bDoorIsDead )
			DoorPaths[i].Path.CollisionRadius -= 10000; // Pretend that no pawn is small enough to use this.
		else DoorPaths.Remove(i--,1); // Remove opened paths.
	}

	MoveTarget = FindPathToward(A,(bAllowDetour && Pawn.bCanPickupInventory  && (Vehicle(Pawn) == None) && (NavigationPoint(A) != None)));
	PreviousNavPath = NavigationPoint(MoveTarget);
	if( PreviousNavPath!=None && PreviousNavPath.bBlocked ) // Shouldn't be possible, but just in case.
		PreviousNavPath = None;

	// Un-setup path finding.
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = false;
	for( i=0; i<DoorPaths.Length; ++i )
		DoorPaths[i].Path.CollisionRadius += 10000;

	return (MoveTarget!=None);
}
function bool FindBestPathTo( vector Dest )
{
	local int i;

	// Setup special path finding.
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = true;
	for( i=0; i<DoorPaths.Length; ++i )
	{
		if( DoorPaths[i].Door.bSealed && !DoorPaths[i].Door.bDoorIsDead )
			DoorPaths[i].Path.CollisionRadius -= 10000; // Pretend that no pawn is small enough to use this.
		else DoorPaths.Remove(i--,1); // Remove opened paths.
	}

	MoveTarget = FindPathTo(Dest);
	PreviousNavPath = NavigationPoint(MoveTarget);
	if( PreviousNavPath!=None && PreviousNavPath.bBlocked ) // Shouldn't be possible, but just in case.
		PreviousNavPath = None;

	// Un-setup path finding.
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = false;
	for( i=0; i<DoorPaths.Length; ++i )
		DoorPaths[i].Path.CollisionRadius += 10000;

	return (MoveTarget!=None);
}

function bool PickRetreatDestination()
{
	local actor BestPath;

	if ( FindInventoryGoal(0) )
		return true;

	if ( (RouteGoal == None) || (Pawn.Anchor == RouteGoal) || Pawn.ReachedDestination(RouteGoal) )
	{
		RouteGoal = GetRandomDest();
		BestPath = RouteCache[0];
		if ( RouteGoal == None )
			return false;
	}

	if ( BestPath!=None )
		MoveTarget = BestPath;
	else if( !FindBestPathToward(RouteGoal,true,true) )
	{
		RouteGoal = None;
		return false;
	}
	return true;
}
function bool FindRoamDest()
{
	local actor BestPath;

	if ( Pawn.FindAnchorFailedTime == Level.TimeSeconds )
	{
		// couldn't find an anchor.
		GoalString = "No anchor "$Level.TimeSeconds;
		if ( Pawn.LastValidAnchorTime > 5 )
		{
			if ( bSoaking )
				SoakStop("NO PATH AVAILABLE!!!");
			else
			{
				if ( (NumRandomJumps > 4) || PhysicsVolume.bWaterVolume )
				{
					Pawn.Health = 0;
					if ( (Vehicle(Pawn) != None) && (Vehicle(Pawn).Driver != None) )
						Vehicle(Pawn).Driver.KilledBy(Vehicle(Pawn).Driver);
					else
						Pawn.Died( self, class'Suicided', Pawn.Location );
					return true;
				}
				else
				{
					// jump
					NumRandomJumps++;
					if ( (Vehicle(Pawn) == None) && (Pawn.Physics != PHYS_Falling) )
					{
						Pawn.SetPhysics(PHYS_Falling);
						Pawn.Velocity = 0.5 * Pawn.GroundSpeed * VRand();
						Pawn.Velocity.Z = Pawn.JumpZ;
					}
				}
			}
		}
		//log(self$" Find Anchor failed!");
		return false;
	}
	NumRandomJumps = 0;
	GoalString = "Find roam dest "$Level.TimeSeconds;
	
	if( BotSupportTimer>Level.TimeSeconds && BotSupportActor!=None )
	{
		if( ActorReachable(BotSupportActor) )
		{
			BestPath = BotSupportActor;
			BotSupportTimer = Level.TimeSeconds-1;
			BotSupportActor = None;
		}
		else if ( FindBestPathToward(BotSupportActor,true,false) )
			BestPath = MoveTarget;
		else BotSupportTimer = Level.TimeSeconds-1;
	}
	if( BestPath==None )
	{
		switch( Personality )
		{
		case 0: // Follow another bot
			if( FollowingPawn==None || FollowingPawn.Health<=0 )
			{
				FollowingPawn = None;
				FindFollow();
				if( FollowingPawn==None ) // Only bot alive?
				{
					Personality = 255;
					goto'RandomMove';
				}
			}
			if( ActorReachable(FollowingPawn) )
				return false; // Roam nearby.
			if ( FindBestPathToward(FollowingPawn,true,false) )
				BestPath = MoveTarget;
			else FollowingPawn = None;
			break;
		case 1: // Follow biggest group
			if( LastBestGroup==None || NextGroupTimer<Level.TimeSeconds || Pawn.Anchor==LastBestGroup || Pawn.ReachedDestination(LastBestGroup) )
			{
				LastBestGroup = None;
				NextGroupTimer = Level.TimeSeconds + FRand()*5.f + 4.f;
				FindGroupMove();
				
				if( LastBestGroup==None )
					return false;
			}
			if ( FindBestPathToward(LastBestGroup,true,false) )
				BestPath = MoveTarget;
			else LastBestGroup = None;
			break;
		default: // Random roam
RandomMove:
			if ( (RouteGoal == None) || (Pawn.Anchor == RouteGoal)
				|| Pawn.ReachedDestination(RouteGoal) )
			{
				RouteGoal = GetRandomDest();
				BestPath = RouteCache[0];
				if ( RouteGoal == None )
				{
					if ( bSoaking && (Physics != PHYS_Falling) )
						SoakStop("COULDN'T FIND ROAM DESTINATION");
					return false;
				}
			}
			if ( BestPath == None && FindBestPathToward(RouteGoal,true,false) )
				BestPath = MoveTarget;
		}
	}
	if ( BestPath != None )
	{
		MoveTarget = BestPath;
		SetAttractionState();
		return true;
	}
	if ( bSoaking && (Physics != PHYS_Falling) )
		SoakStop("COULDN'T FIND ROAM PATH TO "$RouteGoal);
	RouteGoal = None;
	FreeScript();
	return false;
}
final function FindFollow() // Pick randomized pawn but desire for nearest.
{
	local Controller C,Best;
	local float Score,BestScore;
	
	for( C=Level.ControllerList; C!=None; C=C.nextController )
		if( C!=Self && C.bIsPlayer && KFPawn(C.Pawn)!=None && C.Pawn.Health>0 )
		{
			if( KFInvBots(C)!=None && KFInvBots(C).FollowingPawn==Pawn ) // Ignore bots following me already.
				continue;
			Score = VSizeSquared(C.Pawn.Location-Pawn.Location)*(FRand()+0.5);
			if( Best==None || Score<BestScore )
			{
				Best = C;
				BestScore = Score;
			}
		}
	if( Best==None )
		return;
	if( KFInvBots(Best)!=None && KFInvBots(Best).FollowingPawn!=None )
		FollowingPawn = KFInvBots(Best).FollowingPawn;
	else FollowingPawn = Best.Pawn;
}
final function FindGroupMove()
{
	local Controller C,Best;
	local NavigationPoint N,BestN;
	local float Score,BestScore;
	local KFPawn K;
	
	for( C=Level.ControllerList; C!=None; C=C.nextController )
		if( C!=Self && C.bIsPlayer && KFPawn(C.Pawn)!=None && C.Pawn.Health>0 && Rand(4)<=2 )
		{
			if( KFInvBots(C)!=None && KFInvBots(C).Personality<=1 ) // Ignore bots following other bots.
				continue;

			// Set base score.
			Score = FRand()*100.f - FMin(VSize(C.Pawn.Location-Pawn.Location),3000.f)*0.05;

			// Add more score for every player nearby.
			foreach CollidingActors(class'KFPawn',K,800.f,C.Pawn.Location)
				if( K!=C.Pawn && K!=Pawn && K.Health>0 )
					Score+=((30.f*FRand()) + 30.f);
			
			if( Best==None || Score>BestScore )
			{
				Best = C;
				BestScore = Score;
			}
		}
	
	if( Best==None )
		return;
	
	for( N=Level.NavigationPointList; N!=None; N=N.nextNavigationPoint )
	{
		Score = VSizeSquared(N.Location-Best.Pawn.Location);
		if( Score>1000000.f || VSizeSquared(N.Location-Pawn.Location)<10000.f ) // 1000 / 100
			continue;
		Score*=(0.5+FRand());
		if( !FastTrace(N.Location,Best.Pawn.Location) )
			Score = (Score+1000.f)*2.f;
		if( BestN==None || BestScore>Score )
		{
			BestN = N;
			BestScore = Score;
		}
	}
	LastBestGroup = BestN;
}

final function bool VerifyBlockingVolume( BlockingVolume V )
{
	local bool bPlayers,bMonsters;
	local int i;

	if( V==None || !V.bClassBlocker )
		return false;
	for( i=0; i<V.BlockedClasses.Length; ++i )
	{
		bPlayers = bPlayers || ClassIsChildOf(V.BlockedClasses[i],class'KFHumanPawn');
		bMonsters = bMonsters || ClassIsChildOf(V.BlockedClasses[i],class'KFMonster');
	}
	return (bPlayers && !bMonsters);
}
function bool NotifyHitWall(vector HitNormal, actor Wall)
{
	if( PreviousNavPath!=None )
	{
		if( VerifyBlockingVolume(BlockingVolume(Wall)) )
		{
			// debugf;
			TempBlockedPaths.Insert(0,1);
			TempBlockedPaths[0] = PreviousNavPath;
			if( TempBlockedPaths.Length>4 )
				TempBlockedPaths.Length = 4;
			PreviousNavPath = None;
		}
	}
	if( CurrentPath!=None && KFDoorMover(Wall)!=None && KFDoorMover(Wall).bSealed && !KFDoorMover(Wall).bDisallowWeld )
	{
		AddSealPath(CurrentPath,KFDoorMover(Wall));
		MoveTarget = Pawn.Anchor;
	}
	return Super.NotifyHitWall(HitNormal,Wall);
}
final function AddSealPath( ReachSpec Spec, KFDoorMover Door )
{
	local int i;
	
	for( i=0; i<DoorPaths.Length; ++i )
		if( DoorPaths[i].Door==Door && DoorPaths[i].Path==Spec )
			return;

	// debugf;
	i = DoorPaths.Length;
	DoorPaths.Length = i+1;
	DoorPaths[i].Door = Door;
	DoorPaths[i].Path = Spec;
}

function Possess(Pawn aPawn)
{
	Super.Possess(aPawn);
	if( Vehicle(Pawn)==none && Pawn!=None )
	{
		Pawn.MaxFallSpeed = FMax(Pawn.MaxFallSpeed,2500.f); // Hack, but to prevent bots from keep dying at offices.
		if( xPawn(Pawn)!=None )
		{
			xPawn(Pawn).bCanDoubleJump = true; // To stop them from getting stuck at jumps only zeds can make.
			xPawn(Pawn).MaxMultiJump = 1;
			xPawn(Pawn).MultiJumpRemaining = 1;
		}
	}
}
final function int GetMinHealingValue()
{
	if( (Level.TimeSeconds-LastEnemyEncounter)>10.f )
		return 99;
	return 75;
}

function SetCombatTimer()
{
	SetTimer(0.16f, True);
}
function PawnDied(Pawn P)
{
	FavoriteWeapon = None; // Pick new favorite next wave.
	TempBlockedPaths.Length = 0; // Reset blocked paths list.
	DoorPaths.Length = 0;
	Super.PawnDied(P);
}
final function SetFaveGun() // Pick weapon of choise from trader.
{
	local byte Index;
	local int i;
	local class<Pickup> Best;
	local float Desire,BestDesire;

	if( KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill==None )
		return;
	if( Mute.ItemForSale.Length==0 )
		Mute.BuildSaleList();

	Index = KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill.Default.PerkIndex;

	for( i=0; i<Mute.ItemForSale.Length; ++i )
		if( Class<KFWeaponPickup>(Mute.ItemForSale[i])!=None && (Index==Class<KFWeaponPickup>(Mute.ItemForSale[i]).Default.CorrespondingPerkIndex
			|| Mute.NonPerkIndex==Class<KFWeaponPickup>(Mute.ItemForSale[i]).Default.CorrespondingPerkIndex) )
		{
			Desire = Mute.ItemForSale[i].Default.MaxDesireability * (FRand()*0.5 + 1.f);
			if( Best==None || Desire>BestDesire )
			{
				Best = Mute.ItemForSale[i];
				BestDesire = Desire;
			}
		}
	if( Best!=None )
	{
		FavoriteWeapon = class<Weapon>(Best.Default.InventoryType);
		// debugf;
	}
}
function float RateWeapon(Weapon W)
{
	local float R;

	if( !W.bMeleeWeapon && W.AmmoAmount(0)<=0 )
		return -2;

	R = (W.GetAIRating() + FRand() * 0.05);
	if( W.Class==FavoriteWeapon )
		R*=1.5f;
	if( Class<KFWeaponPickup>(W.PickupClass)!=None && WeaponIsForPerk(Class<KFWeaponPickup>(W.PickupClass)) )
		R*=1.25f;
	if( !W.bMeleeWeapon && Enemy!=None && VSize(Enemy.Location-Pawn.Location)>W.GetFireMode(0).MaxRange() )
		R*=0.15;
	return R;
}
function float AdjustDesireFor(Pickup P)
{
	if( FavoriteWeapon!=None && FavoriteWeapon==P.InventoryType )
		return 10.f;
	if( KFWeaponPickup(P)!=None && (!WeaponIsForPerk(Class<KFWeaponPickup>(P.Class)) || KFWeaponPickup(P).Weight>(KFHumanPawn(Pawn).MaxCarryWeight - KFHumanPawn(Pawn).CurrentWeight)) )
		return -1000.f;
	return Super.AdjustDesireFor(P);
}
final function bool WeaponIsForPerk( class<KFWeaponPickup> Wep )
{
	if( KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill==None )
		return true;
	return (Wep.Default.CorrespondingPerkIndex==KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill.Default.PerkIndex || Wep.Default.CorrespondingPerkIndex==Mute.NonPerkIndex);
}
function bool ShouldGoShopping()
{
	// Can't shop if the shop ain't open
	if( DZ_GameType(Level.Game).bWaveInProgress )
		return false;

	// Don't need to shop if we've just shopped
	if( LastShopTime>level.TimeSeconds )
		return false;

	// At the end of the day, it's all about having money, really
	return (PlayerReplicationInfo.score>=100);
}
final function bool ShouldBegForCash()
{
	local Controller C;
	local array<PlayerController> PC;
	local byte i;

	if( DZ_GameType(Level.Game).bWaveInProgress || AnswerBegger!=None )
		return false;

	if( PlayerReplicationInfo.Score<1000 && LastShopTime<level.TimeSeconds ) // Beg if low on dosh and needs to go shop yet.
	{
		for( C=Level.ControllerList; C!=None; C=C.nextController )
			if( KFInvBots(C)!=None && KFInvBots(C).AnswerBeg(Pawn,PlayerReplicationInfo.Score) && ActorReachable(C.Pawn) )
			{
				BeggingTarget = KFInvBots(C);
				BeggingTarget.AnswerBegger = Self;
				SendMessage(None, 'SUPPORT', 2, 0.5f, ''); // I need some money!
				GoToState('BeggingCash','Begin');
				return true;
			}
	}
	else if( PlayerReplicationInfo.Score>900 )
	{
		for( C=Level.ControllerList; C!=None; C=C.nextController )
			if( PlayerController(C)!=None && KFPawn(C.Pawn)!=None && C.PlayerReplicationInfo.Score<250 && ActorReachable(C.Pawn) )
				PC[PC.Length] = PlayerController(C);

		while( PC.Length>0 )
		{
			i = Rand(PC.Length);
			DonatePlayer = PC[i];
			PC.Remove(i,1);
			for( C=Level.ControllerList; C!=None; C=C.nextController )
				if( C!=Self && KFInvBots(C)!=None && KFInvBots(C).DonatePlayer==DonatePlayer )
				{
					DonatePlayer = None;
					break;
				}
			if( DonatePlayer!=None )
			{
				SendMessage(None, 'ALERT', 2, 0.25f, '');
				GoToState('GivePoorPlayerCash','Begin');
				return true;
			}
		}
	}
	return false;
}
final function bool AnswerBeg( Pawn Other, int OtherCash )
{
	if( BeggingTarget!=None || AnswerBegger!=None || (PlayerReplicationInfo.Score-OtherCash)<800 || Pawn==None 
	|| VSize(Pawn.Location-Other.Location)>1000.f || Enemy!=None )
		return false;
	return true;
}
function AnswerBeggerNow()
{
	if( AnswerBegger==None || AnswerBegger.Pawn==None || !ActorReachable(AnswerBegger.Pawn) )
	{
		if( AnswerBegger!=None )
		{
			SendMessage(None, 'ACK', 1, 1.5f, ''); // No!
			AnswerBegger = None;
		}
		return;
	}
	SendMessage(None, 'ACK', 0, 1.5f, ''); // Ok!
	GoToState('RespondToBeg');
}

function rotator AdjustAim(FireProperties FiredAmmunition, vector projStart, int aimerror)
{
	local rotator FireRotation, TargetLook;
	local float FireDist, TargetDist, ProjSpeed,TravelTime, TossedZ;
	local actor HitActor;
	local vector FireSpot, FireDir, TargetVel, HitLocation, HitNormal;
	local int realYaw;
	local bool bDefendMelee, bClean, bLeadTargetNow;

	if ( FiredAmmunition.ProjectileClass != None )
	{
		TossedZ = FiredAmmunition.ProjectileClass.default.TossZ;
		projspeed = FiredAmmunition.ProjectileClass.default.speed;
	}

	// make sure bot has a valid target
	if ( Target == None )
	{
		Target = Enemy;
		if ( Target == None )
			return Rotation;
	}

	if ( Pawn(Target) != None )
		Target = Pawn(Target).GetAimTarget();

	FireSpot = Target.Location;
	TargetDist = VSize(Target.Location - Pawn.Location);

	// perfect aim at stationary objects
	if ( Pawn(Target) == None )
	{
		if ( !FiredAmmunition.bTossed )
			return rotator(Target.Location - projstart);
		else
		{
			FireDir = AdjustToss(projspeed,ProjStart,Target.Location-(vect(0,0,1)*TossedZ),true);
			SetRotation(Rotator(FireDir));
			return Rotation;
		}
	}

	bLeadTargetNow = FiredAmmunition.bLeadTarget && bLeadTarget;
	bDefendMelee = ( (Target == Enemy) && DefendMelee(TargetDist) );
	aimerror = AdjustAimError(aimerror,TargetDist,bDefendMelee,FiredAmmunition.bInstantHit, bLeadTargetNow);

	// lead target with non instant hit projectiles
	if ( bLeadTargetNow )
	{
		TargetVel = Target.Velocity;
		TravelTime = TargetDist/projSpeed;
		// hack guess at projecting falling velocity of target
		if ( Target.Physics == PHYS_Falling )
		{
			if ( Target.PhysicsVolume.Gravity.Z <= Target.PhysicsVolume.Default.Gravity.Z )
				TargetVel.Z = FMin(TargetVel.Z + FMax(-400, Target.PhysicsVolume.Gravity.Z * FMin(1,TargetDist/projSpeed)),0);
			else
			{
				TargetVel.Z = TargetVel.Z + 0.5 * TravelTime * Target.PhysicsVolume.Gravity.Z;
				FireSpot = Target.Location + TravelTime*TargetVel;
			 	HitActor = Trace(HitLocation, HitNormal, FireSpot, Target.Location, false);
			 	bLeadTargetNow = false;
			 	if ( HitActor != None )
			 		FireSpot = HitLocation + vect(0,0,2);
			}
		}

		if ( bLeadTargetNow )
		{
			// more or less lead target (with some random variation)
			FireSpot += FMin(1, 0.7 + 0.6 * FRand()) * TargetVel * TravelTime;
			FireSpot.Z = FMin(Target.Location.Z, FireSpot.Z);
		}
		if ( (Target.Physics != PHYS_Falling) && (FRand() < 0.55) && (VSize(FireSpot - ProjStart) > 1000) )
		{
			// don't always lead far away targets, especially if they are moving sideways with respect to the bot
			TargetLook = Target.Rotation;
			if ( Target.Physics == PHYS_Walking )
				TargetLook.Pitch = 0;
			bClean = ( ((Vector(TargetLook) Dot Normal(Target.Velocity)) >= 0.71) && FastTrace(FireSpot, ProjStart) );
		}
		else // make sure that bot isn't leading into a wall
			bClean = FastTrace(FireSpot, ProjStart);
		if ( !bClean)
		{
			// reduce amount of leading
			if ( FRand() < 0.3 )
				FireSpot = Target.Location;
			else
				FireSpot = 0.5 * (FireSpot + Target.Location);
		}
	}

	bClean = false; //so will fail first check unless shooting at feet
	if ( FiredAmmunition.bTrySplash && (Pawn(Target) != None) && ((Skill >=4) || bDefendMelee)
		&& (((Target.Physics == PHYS_Falling) && (Pawn.Location.Z + 80 >= Target.Location.Z))
			|| ((Pawn.Location.Z + 19 >= Target.Location.Z) && (bDefendMelee || (skill > 6.5 * FRand() - 0.5)))) )
	{
	 	HitActor = Trace(HitLocation, HitNormal, FireSpot - vect(0,0,1) * (Target.CollisionHeight + 6), FireSpot, false);
 		bClean = (HitActor == None);
		if ( !bClean )
		{
			FireSpot = HitLocation + vect(0,0,3);
			bClean = FastTrace(FireSpot, ProjStart);
		}
		else
			bClean = ( (Target.Physics == PHYS_Falling) && FastTrace(FireSpot, ProjStart) );
	}
	if ( Pawn.Weapon != None && Pawn.Weapon.bSniping && Stopped() && (Skill > 5 + 6 * FRand()) )
	{
		// try head
 		FireSpot.Z = Target.Location.Z + 0.9 * Target.CollisionHeight;
 		bClean = FastTrace(FireSpot, ProjStart);
	}

	if ( !bClean )
	{
		//try middle
		FireSpot.Z = Target.Location.Z;
 		bClean = FastTrace(FireSpot, ProjStart);
	}
	if ( FiredAmmunition.bTossed && !bClean && bEnemyInfoValid )
	{
		FireSpot = LastSeenPos;
	 	HitActor = Trace(HitLocation, HitNormal, FireSpot, ProjStart, false);
		if ( HitActor != None )
		{
			bCanFire = false;
			FireSpot += 2 * Target.CollisionHeight * HitNormal;
		}
		bClean = true;
	}

	if( !bClean )
	{
		// try head
 		FireSpot.Z = Target.Location.Z + 0.9 * Target.CollisionHeight;
 		bClean = FastTrace(FireSpot, ProjStart);
	}
	if ( !bClean && (Target == Enemy) && bEnemyInfoValid )
	{
		FireSpot = LastSeenPos;
		if ( Pawn.Location.Z >= LastSeenPos.Z )
			FireSpot.Z -= 0.4 * Enemy.CollisionHeight;
	 	HitActor = Trace(HitLocation, HitNormal, FireSpot, ProjStart, false);
		if ( HitActor != None )
		{
			FireSpot = LastSeenPos + 2 * Enemy.CollisionHeight * HitNormal;
			if ( Pawn.Weapon != None && Pawn.Weapon.SplashDamage() && (Skill >= 4) )
			{
			 	HitActor = Trace(HitLocation, HitNormal, FireSpot, ProjStart, false);
				if ( HitActor != None )
					FireSpot += 2 * Enemy.CollisionHeight * HitNormal;
			}
			if ( Pawn.Weapon != None && Pawn.Weapon.RefireRate() < 0.99 )
				bCanFire = false;
		}
	}

	// adjust for toss distance
	if ( FiredAmmunition.bTossed )
		FireDir = AdjustToss(projspeed,ProjStart,FireSpot-(vect(0,0,1)*TossedZ),true);
	else
	{
		FireDir = FireSpot - ProjStart;
		if ( Pawn(Target) != None )
			FireDir = FireDir + Pawn(Target).GetTargetLocation() - Target.Location;
	}

	FireRotation = Rotator(FireDir);
	realYaw = FireRotation.Yaw;

	FireRotation.Yaw = SetFireYaw(FireRotation.Yaw + aimerror);
	FireDir = vector(FireRotation);
	// avoid shooting into wall
	FireDist = FMin(VSize(FireSpot-ProjStart), 400);
	FireSpot = ProjStart + FireDist * FireDir;
	HitActor = Trace(HitLocation, HitNormal, FireSpot, ProjStart, false);
	if ( HitActor != None )
	{
		if ( HitNormal.Z < 0.7 )
		{
			FireRotation.Yaw = SetFireYaw(realYaw - aimerror);
			FireDir = vector(FireRotation);
			FireSpot = ProjStart + FireDist * FireDir;
			HitActor = Trace(HitLocation, HitNormal, FireSpot, ProjStart, false);
		}
		if ( HitActor != None )
		{
			FireSpot += HitNormal * 2 * Target.CollisionHeight;
			if ( Skill >= 4 )
			{
				HitActor = Trace(HitLocation, HitNormal, FireSpot, ProjStart, false);
				if ( HitActor != None )
					FireSpot += Target.CollisionHeight * HitNormal;
			}
			FireDir = Normal(FireSpot - ProjStart);
			FireRotation = rotator(FireDir);
		}
	}
	InstantWarnTarget(Target,FiredAmmunition,vector(FireRotation));
	ShotTarget = Pawn(Target);

	SetRotation(FireRotation);
	return FireRotation;
}

final function SendChatMsg( string S )
{
	Level.Game.Broadcast(self, "["$PlayerReplicationInfo.GetCallSign()$"] "$S, 'TeamSayQuiet');
}
final function OrderBot( Controller Other, optional byte OrderID )
{
	if( OrderID==0 )
	{
		if( bGuardPosition )
			OrderID = 3;
		else if( AssistingPlayer==Other )
			OrderID = 2;
		else OrderID = 1;
	}
	switch( OrderID )
	{
	case 1:
		AssistingPlayer = Other;
		bGuardPosition = false;
		SendChatMsg("I got your back, "$Other.GetHumanReadableName()$".");
		break;
	case 2:
		if( Other.Pawn==None )
			return;
		AssistingPlayer = None;
		bGuardPosition = true;
		GuardingPosition = Other.Pawn.Location;
		SendChatMsg("I'll hold this position.");
		break;
	case 3:
		bGuardPosition = false;
		AssistingPlayer = None;
		SendChatMsg("I'm on my own then.");
		break;
	default:
		SendChatMsg("Fuck YOU!!!");
		return;
	}
	SendMessage(Other.PlayerReplicationInfo, 'ACK', 0, 1.5f, 'Local'); // Ok!
}
final function bool GetBuyDesire( class<Pickup> aItem, out float Desire )
{
	local class<kfWeaponPickup> aWeapon;
	local Inventory InvIt;
	local KFWeapon Weap;
	local float Cost;
	local bool bFave;

	aWeapon = class<KFWeaponPickup>(aItem);

	if( aWeapon!=none && (aWeapon.default.InventoryType==FavoriteWeapon || WeaponIsForPerk(aWeapon)) )
	{
		Desire = aWeapon.Default.MaxDesireability;
		if( aWeapon.default.InventoryType==FavoriteWeapon )
		{
			bFave = true;
			Desire *= 4.f; // Must get favorite weapon.
		}
		Desire*=(FRand()*0.5+1.f); // Randomize it a little...

		for(InvIt=Pawn.Inventory; InvIt!=none; InvIt=InvIt.Inventory)
		{
			if( InvIt.PickupClass==aWeapon )
			{
				Weap = KFWeapon(InvIt);
				if( Weap==None || Weap.bMeleeWeapon || Weap.AmmoClass[0]==None || Weap.AmmoAmount(0)>=Weap.MaxAmmo(0) )
					return false;
				Cost = aWeapon.default.ammocost*GetVet().Static.GetAmmoCostScaling(KFPlayerReplicationInfo(PlayerReplicationInfo),aWeapon)*Mute.BotAmmoCostScale;
				if( PlayerReplicationInfo.score<int(Cost) )
					return false;
				if( Frag(Weap)!=None && Weap.AmmoAmount(0)>1 ) // Don't go for max nades though, but make sure it carries at least two.
					Desire *= 0.95f;
				else Desire *= 2.5f; // Prioritize ammo purchases more.
				return true;
			}
		}

		// if we didn't find it above, we need to see if we can buy the whole gun, not just ammo
		Cost = aWeapon.default.Cost*GetVet().Static.GetCostScaling(KFPlayerReplicationInfo(PlayerReplicationInfo),aWeapon)*Mute.BotWeaponCostScale;
		if( int(Cost)<=PlayerReplicationInfo.Score && (KFHumanPawn(Pawn).CanCarry(aWeapon.default.weight) || bFave) )
			return true;
		// debugf;
	}
	return false;
}
final function class<KFVeterancyTypes> GetVet()
{
	return KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill;
}
final function bool SellWeapon( KFWeapon W )
{
	if( W==None || W.bKFNeverThrow )
		return false;
	PlayerReplicationInfo.Score+=GetWeaponWorth(W);
	W.Destroy();
	return true;
}
final function int GetWeaponWorth( KFWeapon W )
{
	if( W.SellValue>0 )
		return W.SellValue;
	return class<KFWeaponPickup>(W.PickupClass).Default.Cost*0.75*GetVet().Static.GetCostScaling(KFPlayerReplicationInfo(PlayerReplicationInfo),W.PickupClass);
}
final function class<Pickup> GetBestPurchase()
{
	local int i;
	local class<Pickup> BestBuy;
	local float Des,BestDes;

	if( Mute.ItemForSale.Length==0 )
		Mute.BuildSaleList();
	for(i=0; i<Mute.ItemForSale.Length; i++ )
	{
		if( GetBuyDesire(Mute.ItemForSale[i],Des) && (BestBuy==None || BestDes<Des) )
		{
			BestBuy = Mute.ItemForSale[i];
			BestDes = Des;
		}
	}
	return BestBuy;
}
final function BuyKevlar()
{
	local float Cost;
	local int UnitsAffordable;

	if ( UnrealPawn(Pawn).ShieldStrength>=100 )
		Return;

	Cost = class'Vest'.default.ItemCost * ((100.0 - UnrealPawn(Pawn).ShieldStrength) / 100.0);
	Cost *= (GetVet().static.GetCostScaling(KFPlayerReplicationInfo(PlayerReplicationInfo), class'Vest') * Mute.BotArmorCostScale);

	if ( PlayerReplicationInfo.Score >= Cost )
	{
		PlayerReplicationInfo.Score -= Cost;
		UnrealPawn(Pawn).ShieldStrength = 100;
	}
	else if ( UnrealPawn(Pawn).ShieldStrength>0 )
	{
		Cost = class'Vest'.default.ItemCost/100.f;
		Cost *= (GetVet().static.GetCostScaling(KFPlayerReplicationInfo(PlayerReplicationInfo), class'Vest') * Mute.BotArmorCostScale);

		UnitsAffordable = int(PlayerReplicationInfo.Score / Cost);
		PlayerReplicationInfo.Score -= int(Cost * UnitsAffordable);
		UnrealPawn(Pawn).ShieldStrength += UnitsAffordable;
	}
	PlayerReplicationInfo.Score = int(PlayerReplicationInfo.Score);
}
final function bool SellMostUndesired()
{
	local Inventory I;
	local KFWeapon W,Best;
	local class<KFWeaponPickup> WP;
	local float Score,BestScore;
	
	for( I=Pawn.Inventory; I!=none; I=I.Inventory )
	{
		W = KFWeapon(I);
		if( W!=None && !W.bKFNeverThrow )
		{
			WP = class<KFWeaponPickup>(W.PickupClass);
			Score = 5.f + (WP.Default.Weight * 0.1f) + (FRand()*2.f) * (1.5f - FClamp(float(WP.Default.PowerValue) * 0.0025f,0.f,1.f));
			if( Best==None || Score>BestScore )
			{
				Best = W;
				BestScore = Score;
			}
		}
	}
	if( Best==None )
		return false;
	SellWeapon(Best);
	return true;
}
function DoTrading()
{
	local KFWeapon Weap;
	local class<KFWeaponPickup> BuyWeapClass;
	local int OldCash;
	local float Cost;
	local byte LCount,LCountB;
	local Inventory I,NI;
	local KFHumanPawn P;

	P = KFHumanPawn(Pawn);
	if( P==None )
		return;

	// debugf;
	if( FavoriteWeapon==None )
		SetFaveGun();

	LastShopTime = Level.TimeSeconds+120+60*FRand();

	OldCash = PlayerReplicationInfo.Score + 1;

	// Sell out weapons we don't want
	if( KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill!=None )
	{
		for( I=Pawn.Inventory; I!=none; I=NI )
		{
			NI = I.Inventory;
			Weap = KFWeapon(I);
			if( Weap!=None && !Weap.bKFNeverThrow && Weap.Class!=FavoriteWeapon && !WeaponIsForPerk(class<KFWeaponPickup>(Weap.PickupClass)) )
			{
				// debugf;
				SellWeapon(Weap);
			}
		}
	}

	while ( (PlayerReplicationInfo.Score > 20) && PlayerReplicationInfo.Score!=OldCash && LCount++<10 )
	{
		OldCash = PlayerReplicationInfo.Score;

		BuyWeapClass = class<KFWeaponPickup>(GetBestPurchase());
		if( BuyWeapClass==None )
			Continue;
		Weap = FindWeaponInInv(BuyWeapClass);

		if(Weap!=none) // already own gun, buy ammo
		{
			FillAllAmmo(Weap.GetAmmoClass(0),1.f);
			// debugf;
		}
		else // buy that gun
		{
			// Must sell off inventory to get favorite.
			if( BuyWeapClass.default.InventoryType==FavoriteWeapon )
			{
				while( !P.CanCarry(BuyWeapClass.default.Weight) && ++LCountB<10 && SellMostUndesired() )
				{}
				if( !P.CanCarry(BuyWeapClass.default.Weight) ) // Could not get favorite weapon, no matter what.
				{
					FavoriteWeapon = None; // Try to set new favorite weapon next time.
					++OldCash;
					continue;
				}
			}
			Cost = BuyWeapClass.default.Cost;
			Cost *= (GetVet().Static.GetCostScaling(KFPlayerReplicationInfo(PlayerReplicationInfo),BuyWeapClass) * Mute.BotWeaponCostScale);
			Weap = KFWeapon(Spawn(BuyWeapClass.default.InventoryType));
			if( Weap!=None )
			{
				if ( DZ_GameType(Level.Game) != none )
					DZ_GameType(Level.Game).WeaponSpawned(Weap);
				Weap.UpdateMagCapacity(PlayerReplicationInfo);
				Weap.FillToInitialAmmo();
				Weap.SellValue = Cost * 0.75;
				Weap.GiveTo(Pawn);
			}
			PlayerReplicationInfo.Score -= int(Cost);
			// debugf;
		}
	}
	PlayerReplicationInfo.Score = Max(PlayerReplicationInfo.Score,0); // Make sure we don't fall to negative now.

	if( PlayerReplicationInfo.Score>0 ) // Also purchase armor.
	{
		// debugf;
		BuyKevlar();
	}
	SwitchToBestWeapon();
}
final function int FillAllAmmo( Class<Ammunition> AClass, float PriceScale )
{
    local Inventory I;
    local float Price;
    local Ammunition AM;
    local KFWeapon KW;
    local int c,ol,mxam;
    local float UsedMagCapacity;
    local Boomstick DBShotty;

    if ( AClass == None )
        return 0;

    for ( I=Pawn.Inventory; I != none; I=I.Inventory )
    {
        if ( I.Class == AClass )
            AM = Ammunition(I);
        else if ( KW == None && KFWeapon(I) != None && (Weapon(I).AmmoClass[0] == AClass || Weapon(I).AmmoClass[1] == AClass) )
            KW = KFWeapon(I);
    }

    if ( KW == none || AM == none )
        return 0;

    DBShotty = Boomstick(KW);

    AM.MaxAmmo = AM.default.MaxAmmo;
    if ( KFPlayerReplicationInfo(PlayerReplicationInfo) != none && KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill != none )
        AM.MaxAmmo = int(float(AM.MaxAmmo) * KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill.static.AddExtraAmmoFor(KFPlayerReplicationInfo(PlayerReplicationInfo), AClass));

	mxam = AM.MaxAmmo;
	if( KW==MyGrenades )
		mxam = Min(mxam,4); // Never get more than 4 grenades.

    if ( AM.AmmoAmount >= mxam )
        return 0;

    Price = class<KFWeaponPickup>(KW.PickupClass).default.AmmoCost * KFPlayerReplicationInfo(PlayerReplicationInfo).ClientVeteranSkill.static.GetAmmoCostScaling(KFPlayerReplicationInfo(PlayerReplicationInfo), KW.PickupClass) * Mute.BotAmmoCostScale * PriceScale; // Clip price.

    if ( KW.bHasSecondaryAmmo && AClass == KW.FireModeClass[1].default.AmmoClass )
        UsedMagCapacity = 1; // Secondary Mags always have a Mag Capacity of 1? KW.default.SecondaryMagCapacity;
    else UsedMagCapacity = KW.default.MagCapacity;

    if( KW.PickupClass == class'QHuskGunPickup' )
        UsedMagCapacity = class<QHuskGunPickup>(KW.PickupClass).default.BuyClipSize;
	UsedMagCapacity = Max(UsedMagCapacity,1);

	c = (mxam-AM.AmmoAmount);

	if( Price>0.001f )
		Price = int(float(c) / UsedMagCapacity * Price);
	else Price = 0;

    if ( PlayerReplicationInfo.Score < Price ) // Not enough CASH (so buy the amount you CAN buy).
    {
		c *= (PlayerReplicationInfo.Score/Price);

		if ( c == 0 )
			return 0; // Couldn't even afford 1 bullet.

        AM.AddAmmo(c);
        if( DBShotty != none )
            DBShotty.AmmoPickedUp();

		ol = PlayerReplicationInfo.Score;
		PlayerReplicationInfo.Score = Max(PlayerReplicationInfo.Score - (float(c) / UsedMagCapacity * Price), 0);
        return (ol-PlayerReplicationInfo.Score);
    }

    PlayerReplicationInfo.Score = int(PlayerReplicationInfo.Score-Price);
    AM.AddAmmo(c);
    if( DBShotty != none )
        DBShotty.AmmoPickedUp();
    return Price;
}
function bool GetNearestShop()
{
	local DZ_GameType KFGT;
	local int i,l;
	local float Dist,BDist;
	local ShopVolume Sp;

	KFGT = DZ_GameType(Level.Game);
	if( KFGT==None )
		return false;
	l = KFGT.ShopList.Length;
	for( i=0; i<l; i++ )
	{
		if( !KFGT.ShopList[i].bCurrentlyOpen )
			continue;
		if( !KFGT.ShopList[i].bTelsInit )
			KFGT.ShopList[i].InitTeleports();
		Dist = VSize(KFGT.ShopList[i].Location-Pawn.Location);
		if( Dist<BDist || Sp==None )
		{
			Sp = KFGT.ShopList[i];
			BDist = Dist;
		}
	}
	if( Sp==None )
		return false;
	if( Sp.TelList.Length>0 )
		ShoppingPath = Sp.TelList[Rand(Sp.TelList.Length)];
	else
	{
		if( Sp.BotPoint==None )
		{
			Sp.BotPoint = FindShopPoint(Sp);
			if( Sp.BotPoint==None )
				return false;
		}
		ShoppingPath = Sp.BotPoint;
	}
	if( Sp.MyTrader!=None )
		ShopVolumeActor = Sp.MyTrader;
	else ShopVolumeActor = Sp;

	if( Mute.NextTraderMsg<Level.TimeSeconds )
	{
		SendMessage(None, 'DIRECTION', 0, 15, 'TEAM'); // Get to the Trader
		Mute.NextTraderMsg = Level.TimeSeconds+30.f;
	}
	return true;
}
final function NavigationPoint FindShopPoint( ShopVolume S )
{
	local NavigationPoint N,BN;
	local float Dist,BDist;

	for( N=Level.NavigationPointList; N!=None; N=N.nextNavigationPoint )
	{
		Dist = VSizeSquared(N.Location-S.Location);
		if( BN==None || BDist>Dist )
		{
			BN = N;
			BDist = Dist;
		}
	}
	return BN;
}
function bool EnemyReallyScary()
{
	local Controller C;
	local KFMonster M;
	local byte i;
	local float D;

	for( C=Level.ControllerList; C!=None; C=C.nextController )
	{
		M = KFMonster(C.Pawn);
		if( M==None || M.Health<=0 )
			continue;

		D = VSize(M.Location-Pawn.Location);
		if( M.IsA('DuallBladeGoreFast_King') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear Gorefast KF2 in scream distance
				return true;
		}
		if( M.IsA('DuallBladeGoreFast_STANDARD') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear Gorefast KF2 in scream distance
				return true;
		}
		if( M.IsA('ZombieBrute') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear Brutes in scream distance
				return true;
		}
		if( M.IsA('ZombieTitan_Hulk') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear Titan Hulks in scream distance
				return true;
		}
		if( M.IsA('ZombieSuperSiren') )
		{
			if( D<500.f ) // Fear sirens in scream distance
				return true;
		}
		if( M.IsA('ZombieSirenExP') )
		{
			if( D<700.f ) // Fear sirens EXP in scream distance
				return true;
		}
		if( M.IsA('DSSuportSiren') )
		{
			if( D<700.f ) // Fear support sirens in scream distance
				return true;
		}
		else if( M.IsA('ZombieSuperScrake') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear scrakes in close distance
				return true;
		}
		else if( M.IsA('ZombieButcher') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear maniacs in close distance
				return true;
		}
		else if( M.IsA('ZombieKF2SC') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear scrakes in close distance
				return true;
		}
		else if( M.IsA('KF2ZombieHusk_STANDARD') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear Husks KF2 in close distance
				return true;
		}
		else if( M.IsA('WTFZombiesIncinerator') )
		{
			if( C.Enemy==Pawn && D<200.f ) // Fear Incinerator in close distance
				return true;
		}
		else if( M.IsA('ZombieFleshpoundEX') )
		{
			if( C.Enemy==Pawn && D<1000.f ) // Fear fleshpounds targeting in me.
				return true;
		}
		else if( M.IsA('ZombiesEndy') )
		{
			if( C.Enemy==Pawn && D<1000.f ) // Fear Endy targeting in me.
				return true;
		}
		else if( M.IsA('SubBossPatriarchDK') )
		{
			if( C.Enemy==Pawn && D<1000.f ) // Fear fantom patriach targeting in me.
				return true;
		}
		else if( M.IsA('ZombieFP_STANDARD') )
		{
			if( C.Enemy==Pawn && D<1000.f ) // Fear fleshpounds targeting in me.
				return true;
		}
		else if( M.IsA('MeatPounder') )
		{
			if( C.Enemy==Pawn && D<1000.f ) // Fear MeatPounder targeting in me.
				return true;
		}
		else if( M.IsA('ZombieBloatMother') )
		{
			if( C.Enemy==Pawn && D<1000.f ) // Fear Bloat Mother targeting in me.
				return true;
		}
		if( D<150.f )
		{
			if( Pawn.Health<=100 )
				return true; // Fear all close distance enemies when low on health.
			else if( ++i>3 )
				return true; // Fear group of zeds at close distance
		}
	}
	return false;
}
final function bool ShouldNadeEnemy()
{
	local Controller C;
	local KFMonster M,MM,Best;
	local float D,Score,BestScore;

	for( C=Level.ControllerList; C!=None; C=C.nextController )
	{
		M = KFMonster(C.Pawn);
		if( M==None || M.Health<=0 )
			continue;

		D = VSize(M.Location-Pawn.Location);
		if( D>1000.f || D<300.f || !LineOfSightTo(M) ) // Skip enemies too close or too far...
			continue;
		
		Score = 0.f;
		foreach VisibleCollidingActors(class'KFMonster',MM,600.f,M.Location)
		{
			Score += FMin(MM.Health,200.f) * (1.25f - (VSize(MM.Location-M.Location) / 600.f));
		}
		if( Score>450.f && (Best==None || BestScore<Score) )
		{
			Best = M;
			BestScore = Score;
		}
	}
	if( Best!=None )
	{
		Enemy = Best;
		return true;
	}
	return false;
}
final function float GetEnemyDesire( KFMonster M, bool bCheckedSight )
{
	local float Cost;

	Cost = VSize(M.Location-Pawn.Location);
	if( Cost<100 )
		Cost*=0.5f; // Close range, much bigger threat.
	Cost*=(1.f/FMax(float(M.ScoringValue)*0.001f,0.7f));
	if( M.Health<50 )
		Cost*=0.75f; // Weaklings...
	if( Enemy==M )
		Cost*=0.85f;
	if( !bCheckedSight && !LineOfSightTo(M) )
		Cost*=2.f;
	if( M.Controller!=None && M.Controller.Enemy==Self )
		Cost*=0.85f;
	return Cost;
}
final function FindBetterTarget()
{
	local Controller C;
	local KFMonster P,BP;
	local float Cost,Best;

	for( C=Level.ControllerList; C!=None; C=C.nextController )
	{
		P = KFMonster(C.Pawn);
		if( P==None || P.Health<=0 || !LineOfSightTo(P) || P.bDecapitated )
			continue;
		Cost = GetEnemyDesire(P,true);
		if( BP==None || Best>Cost )
		{
			BP = P;
			Best = Cost;
		}
	}
	if( BP!=None && BP!=Enemy )
	{
		Enemy = BP;
		Target = BP;
	}
}
final function bool TryToHealSelf()
{
	if ( MySyringe==none || MySyringe.ChargeBar() < 0.99f )
		return false;
	GoToState('GoHealSelf');
	return true;
}
function FightEnemy(bool bCanCharge, float EnemyStrength)
{
	if( NextTargetCheck<Level.TimeSeconds )
	{
		FindBetterTarget();	
		NextTargetCheck = Level.TimeSeconds+1.f;
	}
	if( Enemy!=None )
		LastEnemyEncounter = Level.TimeSeconds;
	if( Pawn.Health<GetMinHealingValue() && TryToHealSelf() && !ManyEnemiesAround(Pawn.Location) )
		return;
	if( NextNadeTimer<Level.TimeSeconds && MyGrenades!=None && MyGrenades.HasAmmo() && Rand(3)==0 && ShouldNadeEnemy() )
	{
		NextNadeTimer = Level.TimeSeconds+6.f+FRand()*5.f;
		GoalString = "NadeEnemy";
		GoToState('NadeTarget');
		return;
	}
	else NextNadeTimer = Level.TimeSeconds+1.f+FRand()*4.f;

	if( EnemyReallyScary() )
	{
		GoalString = "Retreat";
		if ( (PlayerReplicationInfo.Team != None) && (FRand() < 0.2) )
			SendMessage(None, 'ALERT', Rand(2)+1, 15, 'TEAM'); // RUN! - Wait for me!
		DoRetreat();
		return;
	}
	Super(Bot).FightEnemy(bCanCharge,EnemyStrength);
}
function YellAt(Pawn Moron)
{
	if ( (Enemy != None) || (Mute.NextYellTime>Level.TimeSeconds) || (FRand() < 0.7) )
		return;

	Mute.NextYellTime = Level.TimeSeconds+5.f+3.f*FRand();
	SendMessage(None, 'INSULT', 1, 5, ''); // Insult Players
	SendChatMsg("Fuck YOU, "$Moron.GetHumanReadableName()$" !!! Hy Tbl u GANDON");
	SendChatMsg("Tbl ZAEBAL Pidor Suka HAXYU !!! B zhopy sebe strelyai, MYDAK !!!!");
}
function NotifyKilled(Controller Killer, Controller Killed, pawn KilledPawn)
{
	if( Killer==Self && Mute.NextYellTime<Level.TimeSeconds && FRand()<0.4 )
	{
		SendMessage(None, 'INSULT', 0, 5, ''); // Insult Specimen
		Mute.NextYellTime = Level.TimeSeconds+10.f+10.f*FRand();
	}
	Super.NotifyKilled(Killer,Killed,KilledPawn);
}

final function bool ValidVoice( name N )
{
	return (N=='INSULT' || N=='DIRECTION' || N=='ALERT' || N=='SUPPORT' || N=='ACK' || N=='AUTO');
}

function SendVoiceMessage(PlayerReplicationInfo Sender,
						  PlayerReplicationInfo Recipient,
						  name messagetype,
						  byte messageID,
						  name broadcasttype,
						  optional Pawn soundSender,
						  optional vector senderLocation)
{
	local Controller P;

	if( ValidVoice(messagetype) )
	{
		for ( P = Level.ControllerList; P != none; P = P.NextController )
		{
			if( P.bIsPlayer && KFPlayerController(P)!=None )
			{
				if( BroadcastType=='Local' )
					P.ClientVoiceMessage(Sender, Recipient, messagetype, messageID, soundSender, senderLocation);
				else KFPlayerController(P).ClientLocationalVoiceMessage(Sender, Recipient, messagetype, messageID, soundSender, senderLocation);
			}
		}
	}
}
function SendMessage(PlayerReplicationInfo Recipient, name MessageType, byte MessageID, float Wait, name BroadcastType)
{
	if( ValidVoice(MessageType) )
	{
		// limit frequency of same message
		if ( (MessageType == OldMessageType) && (MessageID == OldMessageID)
			&& (Level.TimeSeconds - OldMessageTime < Wait) )
			return;

		if ( Level.Game.bGameEnded || Level.Game.bWaitingToStartMatch )
			return;
			
		OldMessageID = MessageID;
		OldMessageType = MessageType;
		OldMessageTime = Level.TimeSeconds;

		if (Pawn != none)
			SendVoiceMessage(PlayerReplicationInfo, Recipient, MessageType, MessageID, BroadcastType, Pawn, Pawn.Location);
		else SendVoiceMessage(PlayerReplicationInfo, Recipient, MessageType, MessageID, BroadcastType, None, Location);
	}
}

final function RequestAssist()
{
	local Controller C;
	
	BotSupportActor = None;
	BotSupportTimer = Level.TimeSeconds+5.f;
	for( C=Level.ControllerList; C!=None; C=C.nextController )
		if( C.bIsPlayer && C!=Self && KFInvBots(C)!=None && C.Pawn!=None && C.Pawn.Health>0 && VSizeSquared(C.Pawn.Location-Pawn.Location)<9000000.f ) // 3000
		{
			KFInvBots(C).BotSupportActor = Pawn;
			KFInvBots(C).BotSupportTimer = Level.TimeSeconds+4.f+FRand()*4.f;
		}
}
function bool SetEnemy( Pawn NewEnemy )
{
	if( Enemy==NewEnemy || KFMonster(NewEnemy)==None || NewEnemy.Health<=0 || (Enemy!=None && GetEnemyDesire(KFMonster(Enemy),false)<GetEnemyDesire(KFMonster(NewEnemy),false)) )
		return false;
	Enemy = NewEnemy;
	EnemyChanged(LineOfSightTo(Enemy));
	if( Mute.NextYellTime<Level.TimeSeconds && FRand()<0.1f )
	{
		SendMessage(None, 'INSULT', 0, 5, ''); // Insult Specimen
		Mute.NextYellTime = Level.TimeSeconds+20.f+20.f*FRand();
	}
	if( BotSupportTimer<Level.TimeSeconds )
		RequestAssist();
	LastEnemyEncounter = Level.TimeSeconds;
	return true;
}
function EnemyAquired()
{
	WhatToDoNext(2);
}
function HearNoise(float Loudness, Actor NoiseMaker)
{
	if ( ((ChooseAttackCounter < 2) || (ChooseAttackTime != Level.TimeSeconds)) && NoiseMaker!=None && NoiseMaker.instigator!=None
	 && FastTrace(NoiseMaker.instigator.Location,Pawn.Location) && SetEnemy(NoiseMaker.instigator) )
		EnemyAquired();
}
event SeePlayer(Pawn SeenPlayer)
{
	if ( ((ChooseAttackCounter < 2) || (ChooseAttackTime != Level.TimeSeconds)) && SetEnemy(SeenPlayer) )
		EnemyAquired();
	if ( Enemy == SeenPlayer )
	{
		VisibleEnemy = Enemy;
		EnemyVisibilityTime = Level.TimeSeconds;
		bEnemyIsVisible = true;
	}
	else if( Enemy==None && WeldAssistTimer<Level.TimeSeconds && KFPawn(SeenPlayer)!=None && SeenPlayer.Health>0 && SeenPlayer.IsHumanControlled() 
		&& VSizeSquared(SeenPlayer.Location-Pawn.Location)<640000.f && Welder(SeenPlayer.Weapon)!=None && ActiveWelder!=None && !IsInState('Shopping') )
		CheckWelderAssist(SeenPlayer,Welder(SeenPlayer.Weapon));
}

// Check if should help player weld a door.
final function CheckWelderAssist( Pawn Other, Welder Weld )
{
	local byte i;
	local WeldFire WF;
	
	for( i=0; i<2; ++i )
	{
		WF = WeldFire(Weld.GetFireMode(i));
		if( WF!=None && WF.bIsFiring && KFDoorMover(WF.LastHitActor)!=None )
		{
			if( !ActorReachable(Other) )
				return;
			TargetDoor = KFDoorMover(WF.LastHitActor);
			AssistWeldMode = i;
			GoToState('WeldAssist');
			return;
		}
	}
}
function SealUpDoor( KFDoorMover Door ) // Called from door whenever bot should unseal this.
{
	if( Enemy!=None && LineOfSightTo(Enemy) && ActiveWelder!=None )
		Return;
	TargetDoor = Door;
	GoToState('UnWeldDoor');
}

event DelayedWarning();

event bool NotifyBump(actor Other)
{
	local Pawn P;

	Disable('NotifyBump');
	P = Pawn(Other);
	if ( (P == None) || (P.Controller == None) || (Enemy == P) )
		return false;
	if ( SetEnemy(P) )
	{
		EnemyAquired();
		return false;
	}

	if ( Enemy == P )
		return false;

	if ( CheckPathToGoalAround(P) )
		return false;

	if ( !AdjustAround(P) )
		CancelCampFor(P.Controller);
	return false;
}
function DamageAttitudeTo(Pawn Other, float Damage)
{
	if ( (Pawn.health > 0) && (Damage > 0) && SetEnemy(Other) )
		EnemyAquired();
}

state GoHealSelf
{
Ignores SeePlayer,HearNoise,NotifyBump,FireWeaponAt,EnemyAquired;

	function BeginState()
	{
		StopFiring();
		HealState = 0;
		SetTimer(0.25f,true);
	}
	function Timer()
	{
		if( Syringe(Pawn.Weapon)==None )
		{
			Pawn.PendingWeapon = MySyringe;
			if( Pawn.Weapon!=None )
				Pawn.Weapon.PutDown();
			else Pawn.ChangedWeapon();
			return;
		}
		if( HealState==0 )
		{
			Pawn.Weapon.StartFire(1);
			HealState++;
		}
		else
		{
			Global.SwitchToBestWeapon();
			WhatToDoNext(8);
		}
	}
	exec function SwitchToBestWeapon();
Begin:
	if( Enemy!=None )
		MoveTo(Normal(Pawn.Location-Enemy.Location)*400.f+VRand()*200.f+Pawn.Location);
	Pawn.Acceleration = vect(0,0,0);
}

function ExecuteWhatToDoNext()
{
	local float WeaponRating;

	SetTimer(0.1,true);
	SwitchToBestWeapon();
	bHasFired = false;
	GoalString = "WhatToDoNext at "$Level.TimeSeconds;
	if ( Pawn == None )
	{
		warn(GetHumanReadableName()$" WhatToDoNext with no pawn");
		return;
	}

	if ( Enemy == None )
	{
		if ( Level.Game.TooManyBots(self) )
		{
			if ( Pawn != None )
			{
				Pawn.Health = 0;
				Pawn.Died( self, class'Suicided', Pawn.Location );
			}
			Destroy();
			return;
		}
		if( Pawn.Health<=80 && TryToHealSelf() )
			return;
		BlockedPath = None;
		bFrustrated = false;
		if (Target == None || (Pawn(Target) != None && Pawn(Target).Health <= 0))
			StopFiring();
	}

	if ( ScriptingOverridesAI() && ShouldPerformScript() )
		return;
	if (Pawn.Physics == PHYS_None)
		Pawn.SetMovementPhysics();
	if ( (Pawn.Physics == PHYS_Falling) && DoWaitForLanding() )
		return;
	if ( (StartleActor != None) && !StartleActor.bDeleteMe && (VSize(StartleActor.Location - Pawn.Location) < StartleActor.CollisionRadius)  )
	{
		Startle(StartleActor);
		return;
	}
	bIgnoreEnemyChange = true;
	if ( (Enemy != None) && ((Enemy.Health <= 0) || (Enemy.Controller == None)) || !EnemyVisible() )
		LoseEnemy();
	if( Enemy!=None && Vehicle(Enemy)!=None )
		Enemy = None; // Shouldn't be attacking turrets.

	bIgnoreEnemyChange = false;

	if( Enemy==None && ((ShouldGoShopping() && GoShopping()) || ShouldBegForCash()) )
		Return;
	else if( LastHealTime<Level.TimeSeconds && FindInjuredAlly() && !EnemyReallyScary() && GoHealing() )
		return;
// #ifdef WITH_AMMO_BOX
	 else if( (SeekingAmmo!=None || (NextAmmoCheckTime<Level.TimeSeconds && GoForMoreAmmo())) && (bHighPriorityAmmo || Enemy==None || !LineOfSightTo(Enemy)) )
		 GoToState('GettingAmmo','Begin');
// #endif
	else if( bGuardPosition && (Enemy==None || !LineOfSightTo(Enemy)) )
		GoToState('GuardingPos');
	else if( Enemy==None && AssistingPlayer!=None && AssistingPlayer.Pawn!=None && NextAssistTimer<Level.TimeSeconds )
		GoAssistPlayer();
	else
	{
		if ( AssignSquadResponsibility() )
		{
			if ( Pawn == None )
				return;
			SwitchToBestWeapon();
			return;
		}
		if ( ShouldPerformScript() )
			return;
		if ( Enemy != None )
			ChooseAttackMode();
		else
		{
			WeaponRating = Pawn.Weapon.CurrentRating/2000;

			if ( FindInventoryGoal(WeaponRating) )
			{
				if ( InventorySpot(RouteGoal) == None )
					GoalString = "fallback - inventory goal is not pickup but "$RouteGoal;
				else GoalString = "Fallback to better pickup "$InventorySpot(RouteGoal).markedItem$" hidden "$InventorySpot(RouteGoal).markedItem.bHidden;
				GotoState('FallBack');
			}
			else
			{
				// No enemy and no ammo to grab. Guess all there is left to do is to chill out
				GoalString = "WhatToDoNext Wander or Camp at "$Level.TimeSeconds;
				WanderOrCamp(true);
			}
		}
	}
}

function bool FindInjuredAlly()
{
	local controller c;
	local SRHumanPawn aKFHPawn; /////KFHumanPawn
	local float AllyDist;
	local float BestDist;
	local bool bGoMedGun;
	local vector Dummy;
	local Actor A;

	InjuredAlly = None;
	if( ManyEnemiesAround(Pawn.Location) )
		return false;
	if( FindMedGun() && MyMedGun.ChargeBar()>0.49f )
		bGoMedGun = true;
	else if( MySyringe==none || MySyringe.ChargeBar()<0.6f )
		return false;

	for( c=level.ControllerList; c!=none; c=c.nextController )
	{
		if( C==Self )
			continue;

		aKFHPawn = SRHumanPawn(c.pawn); ///KFHumanPawn

		// If he's dead. dont bother.
		if( aKFHPawn==none || aKFHPawn.Health<=0 || (aKFHPawn.Health+aKFHPawn.HealthToGive)>=GetMinHealingValue() 
		|| VSizeSquared(aKFHPawn.Location-Pawn.Location)>1000000.f )
			continue;

		if( bGoMedGun )
		{
			A = Pawn.Trace(Dummy,Dummy,aKFHPawn.Location,Pawn.Location,true);
			if( A!=None && A!=aKFHPawn && A.Owner!=aKFHPawn )
				continue;
		}
		else if( !ActorReachable(aKFHPawn) )
			continue;
		AllyDist = VSizeSquared(Pawn.Location - aKFHPawn.Location);
		if( AKFHPawn.Health<40 )
			AllyDist*=0.5f;
		if( InjuredAlly==none || (AllyDist<BestDist) )
		{
			InjuredAlly = aKFHPawn;
			BestDist = AllyDist;
		}
	}
	if( !bGoMedGun && InjuredAlly!=None && ManyEnemiesAround(InjuredAlly.Location) )
		InjuredAlly = None;
	if( InjuredAlly!=None )
	{
		if( InjuredAlly.Health<60 && KFInvBots(InjuredAlly.Controller)!=None && FRand()<0.5 )
			KFInvBots(InjuredAlly.Controller).SendMessage(None, 'SUPPORT', Rand(2), 4.f, ''); // Need healing!
		else if( FRand()<0.35f )
			SendMessage(None, 'AUTO', 5, 1.f, ''); // Hold still, I'm healing you!
		return true;
	}
	return false;
}
final function bool ManyEnemiesAround( vector Point )
{
	local Controller C;
	local byte i;

	for( C=Level.ControllerList; C!=None; C=C.nextController )
	{
		if( KFMonster(C.Pawn)!=None && KFMonster(C.Pawn).Health>0 && VSizeSquared(C.Pawn.Location-Point)<640000.f && FastTrace(Point,C.Pawn.Location) && ++i==5 )
			return true;
	}
	return false;
}
function DoRetreat()
{
	GotoState('Retreating');
}

function bool CanDoHeal()
{
	return (MySyringe!=none && MySyringe.GetFireMode(0).AllowFire() && InjuredAlly!=none && InjuredAlly.Health>0 && (InjuredAlly.Health+InjuredAlly.HealthToGive)<GetMinHealingValue());
}
final function bool CanUseMedHeal()
{
	return (FindMedGun() && MyMedGun.GetFireMode(1).AllowFire() && MyMedGun.ChargeBar()>0.49f && InjuredAlly!=none && InjuredAlly.Health>0 && (InjuredAlly.Health+InjuredAlly.HealthToGive)<GetMinHealingValue());
}
final function bool FindMedGun()
{
	if( MyMedGun!=none && MyMedGun.Owner==Pawn && MyMedGun.ChargeBar()>0.49f )
		return true;

	for( inv=pawn.Inventory; inv!=none; inv=inv.Inventory )
	{
		if( KFMedicGun(inv)!=None || M7A3MMedicGun_DZ(inv)!=None  || M7A3MMedicGun_P(inv)!=None  || M7A3MMedicGunQ(inv)!=None  
		|| M56HealiGunU(inv)!=None || M56HealiGun(inv)!=None  || MP7MMedicGun(inv)!=None )
		{
			MyMedGun = KFWeapon(inv);
			if( MyMedGun.ChargeBar()>0.49f )
				return true;
		}
	}
	MyMedGun = None;
	return false;
}
function bool GoHealing()
{
	if( InjuredAlly!=none && LastHealTime<Level.TimeSeconds )
	{
		LastHealTime = Level.TimeSeconds+2.f;
		GoalString = "HEALING";
		if( CanUseMedHeal() )
			GotoState('MedGunHealing');
		else GotoState('Healing');
		return true;
	}
	else return false;
}
function TimedFireWeaponAtEnemy()
{
	// debugf;
	if ( Enemy != None )
		FireWeaponAt(Enemy);
	SetTimer(0.15f, True);
}
function bool FireWeaponAt(Actor A)
{
	if ( A == None )
		A = Enemy;
	if ( A == None || !Pawn.CanAttack(A) )
		return false;
	Target = A;
	if ( Pawn.Weapon != None )
	{
		if ( Pawn.Weapon.HasAmmo() )
			return WeaponFireAgain(Pawn.Weapon.RefireRate(),false);
	}
	else
		return WeaponFireAgain(Pawn.RefireRate(),false);

	return false;
}

final function TossCash( int Amount, vector TossDir )
{
	local CashPickup CashPickup;

	PlayerReplicationInfo.Score = int(PlayerReplicationInfo.Score);
	if( PlayerReplicationInfo.Score<=0 || Amount<=0 )
		return;
	Amount = Min(Amount,int(PlayerReplicationInfo.Score));

	TossDir = Normal(TossDir-Pawn.Location)*500.f + Vect(0,0,200);
	CashPickup = Spawn(class'CashPickup',,, Pawn.Location + Pawn.CollisionRadius * vector(Pawn.Rotation));

	if(CashPickup != none)
	{
		CashPickup.CashAmount = Amount;
		CashPickup.bDroppedCash = true;
		CashPickup.RespawnTime = 0;   // Dropped cash doesnt respawn. For obvious reasons.
		CashPickup.Velocity = TossDir;
		CashPickup.DroppedBy = Self;
		CashPickup.InitDroppedPickupFor(None);
		PlayerReplicationInfo.Score -= Amount;

		SendMessage(None, 'AUTO', 4, KFPawn(Pawn).DropCashMessageDelay, ''); // Loads of money!
	}
}
final function PickNextRetMove()
{
	local NavigationPoint N;
	local float Dist,BestDist;
	local int i;
	local vector EnemyDir;

	if( CurrentMov==None )
	{
		for( N=Level.NavigationPointList; N!=None; N=N.nextNavigationPoint )
		{
			Dist = VSizeSquared(N.Location-Pawn.Location);
			if( Dist<10000.f )
			{
				CurrentMov = N;
				GoTo'MoveFound';
			}
			else if( CurrentMov==None || Dist<BestDist )
			{
				CurrentMov = N;
				BestDist = Dist;
			}
		}
		if( CurrentMov==None || !ActorReachable(CurrentMov) )
			return;
		MoveTarget = CurrentMov;
		return;
	}
	if( VSizeSquared(CurrentMov.Location-Pawn.Location)>10000.f )
	{
		if( ActorReachable(CurrentMov) )
		{
			MoveTarget = CurrentMov;
			return;
		}
		if( OldMovesCount>0 )
		{
			MoveTarget = OldMoves[0];
			CurrentMov = OldMoves[0];
		}
		else MoveTarget = None;
		return;
	}
MoveFound:
	MoveTarget = None;
	EnemyDir = Normal(Enemy.Location-Pawn.Location);
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = true;
	for( i=0; i<CurrentMov.PathList.Length; i++ )
	{
		N = CurrentMov.PathList[i].End;
		if( N==CurrentMov || N.bBlocked || !ActorReachable(N) )
			continue;
		Dist = (EnemyDir dot Normal(N.Location-Pawn.Location));
		if( SpecIsOldMove(N) )
			Dist+=0.2f;
		if( MoveTarget==None || Dist<BestDist )
		{
			MoveTarget = N;
			Dist = BestDist;
		}
	}
	for( i=0; i<TempBlockedPaths.Length; ++i )
		TempBlockedPaths[i].bBlocked = false;
	if( MoveTarget!=None )
	{
		PreviousNavPath = NavigationPoint(MoveTarget);
		AddOldMove(CurrentMov);
		CurrentMov = PreviousNavPath;
	}
}
final function bool SpecIsOldMove( NavigationPoint N )
{
	local byte i;

	for( i=0; i<OldMovesCount; i++ )
	{
		if( OldMoves[i]==N )
			return true;
	}
	return false;
}
final function AddOldMove( NavigationPoint N )
{
	local byte i;

	if( OldMovesCount<ArrayCount(OldMoves) )
		OldMoves[OldMovesCount++] = N;
	else
	{
		for( i=1; i<ArrayCount(OldMoves); i++ )
			OldMoves[i-1] = OldMoves[i];
		OldMoves[ArrayCount(OldMoves)-1] = N;
	}
}

function DisplayDebug(Canvas Canvas, out float YL, out float YPos)
{
	Super.DisplayDebug(Canvas,YL, YPos);

	Canvas.SetPos(4,YPos);
	if( Pawn!=None && Pawn.Weapon!=None )
		Canvas.DrawText("    TimerRate "$TimerRate$" TimerCounter "$TimerCounter$" AllowFire0 "$Pawn.Weapon.ReadyToFire(0));
	YPos += YL;
	Canvas.SetPos(4,YPos);
}

function bool WeaponFireAgain(float RefireRate, bool bFinishedFire)
{
	LastFireAttempt = Level.TimeSeconds;
	if ( Target == None )
		Target = Enemy;
	if ( Target != None )
	{
		if( !bFinishedFire && Pawn.Weapon.GetFireMode(0).bIsFiring && Pawn.Weapon.GetFireMode(0).bWaitForRelease )
		{
			// Hack: Unstuck shotguns and husk gun.
			if( !Pawn.Weapon.GetFireMode(0).bFireOnRelease || (Pawn.Weapon.GetFireMode(0).NextFireTime-Level.TimeSeconds)<(-1) )
			{
				// debugf;
				Pawn.Weapon.ServerStopFire(0);
			}
			// else DEBUGF(Pawn.Weapon.GetFireMode(0).bWaitForRelease@Pawn.Weapon.GetFireMode(0).bFireOnRelease@(Pawn.Weapon.GetFireMode(0).NextFireTime-Level.TimeSeconds));
			return false;
		}

		if ( !Pawn.IsFiring() )
		{
			if ( (Pawn.Weapon != None && Pawn.Weapon.bMeleeWeapon) || (!NeedToTurn(Target.Location) && LineOfSightTo(Target)) )
			{
				Focus = Target;
				bCanFire = true;
				bStoppedFiring = false;
				if (Pawn.Weapon != None)
				{
					bFireSuccess = Pawn.Weapon.BotFire(bFinishedFire);
// #if DEBUG_MODE
					// DEBUGF(PlayerReplicationInfo.PlayerName@bFireSuccess);
					// if( !bFireSuccess )
						// DEBUGF("Ready:"@Pawn.Weapon.ReadyToFire(0)@(Pawn.Weapon.ClientState==WS_ReadyToFire)@Pawn.Weapon.GetFireMode(0).AllowFire());
// #endif
				}
				else
				{
					Pawn.ChooseFireAt(Target);
					bFireSuccess = true;
				}
				return bFireSuccess;
			}
			else
			{
				bCanFire = false;
			}
		}
		else if ( bCanFire && ShouldFireAgain(RefireRate))
		{
			if ( (Target != None) && !NeedToTurn(Target.Location) && !Target.bDeleteMe )
			{
				bStoppedFiring = false;
				if (Pawn.Weapon != None)
				{
					bFireSuccess = Pawn.Weapon.BotFire(bFinishedFire);
// #if DEBUG_MODE
					// DEBUGF(PlayerReplicationInfo.PlayerName@bFireSuccess@"1");
					// if( !bFireSuccess )
						// DEBUGF("Ready:"@Pawn.Weapon.ReadyToFire(0)@(Pawn.Weapon.ClientState==WS_ReadyToFire)@Pawn.Weapon.GetFireMode(0).AllowFire());
// #endif
				}
				else
				{
					Pawn.ChooseFireAt(Target);
					bFireSuccess = true;
				}
				return bFireSuccess;
			}
		}
	}
	StopFiring();
	return false;
}

// #ifdef WITH_AMMO_BOX
 final function bool GoForMoreAmmo()
 {
	 local Controller C;
	 local Inventory I;
	 local Weapon W;
	 local float Dist,BDist;
	 local bool bMissing,bAny;
 
	 bWantedAmmo = false;
	 NextAmmoCheckTime = Level.TimeSeconds + FRand()*15.f;
	 
	// // See if has any DOSH, or can buy cheaper from trader.
	 if( PlayerReplicationInfo.Score<150 || !DZ_GameType(Level.Game).bWaveInProgress )
		 return false;
	 
	// // First check our ammo status.
	 for( I=Pawn.Inventory; I!=None; I=I.Inventory )
	 {
		 W = Weapon(I);
		 if( W!=None && !W.bMeleeWeapon && Frag(W)==None && W.GetAmmoClass(0)!=None )
		 {
			 if( W.AmmoStatus(0)<0.4 )
				 bMissing = true;
			 if( W.HasAmmo() )
				 bAny = true;
		 }
	 }
	 if( !bMissing )
		 return false;
	 
	 bHighPriorityAmmo = !bAny;
	// DEBUGF(PlayerReplicationInfo.PlayerName@"get ammo"@bMissing@bAny);
// 
	// // Now try to find nearest ammobox
	 if( SeekingAmmo!=None && bAmmoBoxInUse )
		 SeekingAmmo.UserStatus(false);
	 bAmmoBoxInUse = false;
	 SeekingAmmo = None;
	 for( C=Level.ControllerList; C!=None; C=C.nextController )
		 if( C.bIsPlayer && C.Class==Class'AmmoBoxAI' && AmmoBox(C.Pawn)!=None )
		 {
			 Dist = VSizeSquared(C.Pawn.Location-Pawn.Location);
			 if( SeekingAmmo==None || BDist>Dist )
			 {
				 SeekingAmmo = AmmoBox(C.Pawn);
				 BDist = Dist;
			 }
		 }
	 
	 if( SeekingAmmo==None )
		 return false;
	 bWantedAmmo = true;
	 return true;
 }
// #endif

state Retreating
{
Ignores EnemyNotVisible,NotifyBump,EnemyAquired;

	function BeginState()
	{
		Pawn.bWantsToCrouch = false;
		SetTimer(0.1,true);
	}
	function Timer()
	{
		TimedFireWeaponAtEnemy();
	}
Begin:
	RetreatTime = Level.TimeSeconds+7.f+FRand()*15.f;
	CurrentMov = None;
	OldMovesCount = 0;
	while( RetreatTime>Level.TimeSeconds )
	{
		WaitForLanding();
Moving:
		if( Enemy==None )
		{
			MoveTo(VRand()*300.f+Pawn.Location,None);
			break;
		}
		Timer();
		PickNextRetMove();
		if( MoveTarget==None )
		{
			MoveTo(Normal(Pawn.Location-Enemy.Location)*400.f+VRand()*300.f+Pawn.Location,Enemy);
			break;
		}
		else MoveToward(MoveTarget,Enemy,GetDesiredOffset(),ShouldStrafeTo(MoveTarget));
	}
	WhatToDoNext(44);
	if ( bSoaking )
		SoakStop("STUCK IN RETREAT!");
	goalstring = goalstring$" STUCK IN RETREAT!";
}

state Healing
{
	final function bool TryToHealthTarget() // Healing hack, because syringe acts up for bots.
	{
		local vector V;
		local WeaponFire F;
		local int MedicReward,HealSum;
		local KFPlayerReplicationInfo PRI;

		if( InjuredAlly==None )
			return false;

		// First reject if out of ammo, distance or not visible.
		F = MySyringe.GetFireMode(0);
		V = (InjuredAlly.Location-Pawn.Location);
		if( NextMedicFireTime>Level.TimeSeconds || InjuredAlly.Health<=0 || !F.AllowFire() || Abs(V.Z)>(Pawn.CollisionHeight+InjuredAlly.CollisionHeight+20.f)
		|| (Square(V.X)+Square(V.Y))>Square(Pawn.CollisionRadius+InjuredAlly.CollisionRadius+50.f) || !FastTrace(InjuredAlly.Location,Pawn.Location) )
			return false;
		
		NextMedicFireTime = Level.TimeSeconds+F.FireRate;
		PRI = KFPlayerReplicationInfo(Instigator.PlayerReplicationInfo);
		MySyringe.ConsumeAmmo(0, F.AmmoPerFire);
		MedicReward = MySyringe.HealBoostAmount;

		if ( PRI!=None && PRI.ClientVeteranSkill!=none )
			MedicReward *= PRI.ClientVeteranSkill.Static.GetHealPotency(PRI);
			
		HealSum = MedicReward;

		if ( (InjuredAlly.Health + InjuredAlly.healthToGive + MedicReward) > InjuredAlly.HealthMax )
			MedicReward = Max(InjuredAlly.HealthMax - (InjuredAlly.Health + InjuredAlly.healthToGive),0);

		InjuredAlly.GiveHealth(HealSum, InjuredAlly.HealthMax);

		if ( PRI != None )
		{
            // Give the medic reward money as a percentage of how much of the person's health they healed
			MedicReward = int((FMin(float(MedicReward),InjuredAlly.HealthMax)/InjuredAlly.HealthMax) * 60); // Increased to 80 in Balance Round 6, reduced to 60 in Round 7
			PRI.ReceiveRewardForHealing( MedicReward, InjuredAlly );
		}
		MySyringe.PlayOwnedSound(SoundGroup'KF_InventorySnd.Injector_Fire',SLOT_Interact,F.TransientSoundVolume,,F.TransientSoundRadius,,false);
		MySyringe.IncrementFlashCount(0);
		return true;
	}
	function Timer()
	{
		if( InjuredAlly==None || (InjuredAlly.Health+InjuredAlly.HealthToGive)>=GetMinHealingValue() )
		{
			InjuredAlly = None;
			LastHealTime = level.TimeSeconds+1;
			WhatToDoNext(162);
			return;
		}
		if ( Pawn.Weapon==MySyringe )
			TryToHealthTarget();
	}
	final function SelectSyringe()
	{
		if( Pawn.Weapon==MySyringe )
			return;
		Pawn.PendingWeapon = MySyringe;
		if ( Pawn.Weapon==None )
			Pawn.ChangedWeapon();
		else if( !Pawn.Weapon.HasAmmo() ) // Most likely weapon is stuck here.
		{
			Pawn.Weapon.PutDown();
			Pawn.Weapon.ClientState = WS_PutDown;
			Pawn.Weapon.Timer();
		}
		else Pawn.Weapon.PutDown();
	}
Begin:
	SwitchToBestWeapon();
	WaitForLanding();
	SetTimer(0.1+FRand()*0.2, True);

	while( InjuredAlly!=None && VSizeSquared(InjuredAlly.Location-Pawn.Location)<1005000.f )
	{
		SelectSyringe();

		if( FindBestPathToward(InjuredAlly,false,false) )
			MoveToward(MoveTarget,InjuredAlly,,false);
		else break;
	}

	LastHealTime = level.TimeSeconds+4;
	WhatToDoNext(163);
	if ( bSoaking )
		SoakStop("STUCK IN HEALING!");
}
state MedGunHealing extends MoveToGoalWithEnemy
{
Ignores SwitchToBestWeapon;

	function bool WeaponFireAgain(float RefireRate, bool bFinishedFire)
	{
		if( Pawn.Weapon==MyMedGun )
		{
			if( NeedToTurn(InjuredAlly.Location) )
				return false;
			MyMedGun.StartFire(1);
			GoToState(,'FinishedMove');
			return true;
		}
		return Super.WeaponFireAgain(RefireRate,bFinishedFire);
	}
	function Timer()
	{
		if( InjuredAlly==None || (InjuredAlly.Health+InjuredAlly.HealthToGive)>=GetMinHealingValue() )
		{
			InjuredAlly = None;
			GoToState(,'FinishedMove');
			return;
		}
		if ( InjuredAlly!=None && Pawn.Weapon==MyMedGun )
		{
			Target = InjuredAlly;
			FireWeaponAt(InjuredAlly);
		}
	}
	final function SelectMedGun()
	{
		if( Pawn.Weapon==MyMedGun )
			return;
		Pawn.PendingWeapon = MyMedGun;
		if ( Pawn.Weapon==None )
			Pawn.ChangedWeapon();
		else if( !Pawn.Weapon.HasAmmo() ) // Most likely weapon is stuck here.
		{
			Pawn.Weapon.PutDown();
			Pawn.Weapon.ClientState = WS_PutDown;
			Pawn.Weapon.Timer();
		}
		else Pawn.Weapon.PutDown();
	}
Begin:
	SelectMedGun();
	SetTimer(0.1, True);
	Pawn.Acceleration = vect(0,0,0);
	Focus = InjuredAlly;
	FinishRotation();
	Sleep(1.f);
FinishedMove:
	SetTimer(0, false);
	Sleep(0.25f);
	LastHealTime = level.TimeSeconds+2;
	WhatToDoNext(166);
}

State BeggingCash
{
Ignores SwitchToBestWeapon;

	function BeginState()
	{
		SetTimer(2,true);
	}
	function EndState()
	{
		if( PlayerReplicationInfo.Score>500 )
			SendMessage(None, 'ACK', 2, 1.5f, ''); // Thanks!
		if( BeggingTarget!=None )
		{
			BeggingTarget.AnswerBegger = None;
			BeggingTarget = None;
		}
	}
	function Timer()
	{
		if( BeggingTarget==None || BeggingTarget.Pawn==None || BeggingTarget.AnswerBegger!=Self )
		{
			EndState();
			WhatToDoNext(35);
			return;
		}
		BeggingTarget.AnswerBeggerNow();
	}
Begin:
	Pawn.Acceleration = vect(0,0,0);
	Focus = BeggingTarget.Pawn;
	Stop;
}
State RespondToBeg
{
Ignores AnswerBeggerNow;

	function BeginState()
	{
		SetTimer(0,false);
	}
	function EndState()
	{
		AnswerBegger = None;
	}
	final function vector GetMoveDest( Actor T )
	{
		local vector D;

		D = (T.Location-Pawn.Location);
		return Pawn.Location+Normal(D)*(VSize(D)-(Pawn.CollisionRadius+T.CollisionRadius+50.f));
	}
	function Timer()
	{
		if( AnswerBegger==None || AnswerBegger.Pawn==None || !CanSee(AnswerBegger.Pawn) || AnswerBegger.PlayerReplicationInfo.Score>600 )
			WhatToDoNext(38);
		else TossCash(50,AnswerBegger.Pawn.Location);
	}
Begin:
	MoveTo(GetMoveDest(AnswerBegger.Pawn),AnswerBegger.Pawn,false);
	Pawn.Acceleration = vect(0,0,0);
	Focus = AnswerBegger.Pawn;
	FinishRotation();
	SetTimer(0.2,true);
	Sleep(2.f);
	WhatToDoNext(39);
}
State GivePoorPlayerCash extends RespondToBeg
{
	function BeginState()
	{
		SetTimer(0.2,true);
	}
	function EndState()
	{
		DonatePlayer = None;
	}
	function Timer()
	{
		if( DonatePlayer==None || DonatePlayer.Pawn==None || !ActorReachable(DonatePlayer.Pawn) || DonatePlayer.PlayerReplicationInfo.Score>600 )
			WhatToDoNext(38);
		else if( VSize(DonatePlayer.Pawn.Location-Pawn.Location)<200 )
		{
			if( MoveTimer>0.f )
			{
				MoveTimer = -1;
				GoToState(,'Done');
			}
			TossCash(50,DonatePlayer.Pawn.Location);
		}
		else if( MoveTimer<=0.f )
			GoToState(,'Begin');
	}
Begin:
	while( true )
		MoveToward(DonatePlayer.Pawn,DonatePlayer.Pawn);
Done:
	Pawn.Acceleration = vect(0,0,0);
	Focus = DonatePlayer.Pawn;
	FinishRotation();
	SetTimer(0.2,true);
	Sleep(2.25f);
	WhatToDoNext(39);
}
function GoAssistPlayer()
{
	GoToState('AssistPlayer','Begin');
}
final function vector PickAssistOffset( Pawn Other )
{
	local vector V;

	V.X = FRand()-0.5f;
	V.Y = FRand()-0.5f;
	return Other.Location+Normal(V)*(Other.CollisionRadius+Pawn.CollisionRadius+20+60*FRand());
}

state OrderMove extends MoveToGoalNoEnemy
{
	function BeginState()
	{
		bForcedDirection = false;
		if ( Skill < 4 )
			Pawn.MaxDesiredSpeed = 0.4 + 0.08 * skill;
		MinHitWall += 0.15;
		Pawn.bAvoidLedges = false;
		Pawn.bStopAtLedges = false;
		Pawn.bCanJump = true;
		bAdjustFromWalls = false;
		Pawn.bWantsToCrouch = false;
		bWallAdjust = false;
	}
	function EndState()
	{
		if ( !bPendingDoubleJump )
			bNotifyApex = false;
		bAdjustFromWalls = true;
		if ( Pawn == None )
			return;
		SetMaxDesiredSpeed();
		MinHitWall -= 0.15;
	}
	function MayFall()
	{
		Pawn.bCanJump = true;
	}
	function bool NotifyHitWall(vector HitNormal, actor Wall)
	{
		// Jump.
		FocalPoint = Destination;
		if ( !bWallAdjust && PickWallAdjust(HitNormal) )
			GotoState(, 'AdjustFromWall');
		else
		{
			if( Pawn.Physics==PHYS_Walking )
				Pawn.DoJump(false);
		}
		return Global.NotifyHitWall(HitNormal,Wall);
	}

Begin:
	Stop;
AdjustFromWall:
	bWallAdjust = true;
	MoveTo(Destination, Focus); 
	MoveTo(FocalPoint,Focus);
	bWallAdjust = false;
	WhatToDoNext(12);
}
State AssistPlayer extends OrderMove
{
Begin:
	SwitchToBestWeapon();
	WaitForLanding();
	if( AssistingPlayer==None || AssistingPlayer.Pawn==None )
		WhatToDoNext(13);
	if( VSize(AssistingPlayer.Pawn.Location-Pawn.Location)<150.f )
		GoTo'PausedMove';
	else if( ActorReachable(AssistingPlayer.Pawn) )
	{
		MoveTo(PickAssistOffset(AssistingPlayer.Pawn),None,false);
PausedMove:
		Focus = None;
		FocalPoint = Pawn.Location+VRand()*800.f;
		NearWall(MINVIEWDIST);
		Pawn.Acceleration = vect(0,0,0);
		Sleep(0.1+FRand());
	}
	else if( FindBestPathToward(AssistingPlayer.Pawn,true,false) )
		MoveToward(MoveTarget,FaceActor(1),GetDesiredOffset(),ShouldStrafeTo(MoveTarget));
	else NextAssistTimer = Level.TimeSeconds+5.f+FRand()*5.f;
	WhatToDoNext(13);
	if ( bSoaking )
		SoakStop("STUCK IN FOLLOWING!");
}
state GuardingPos extends OrderMove
{
	final function bool CloseEnough()
	{
		local vector V;
		
		V = Pawn.Location-GuardingPosition;
		return (Abs(V.Z)<Pawn.CollisionHeight && (Square(V.X)+Square(V.Y))<Square(Pawn.CollisionRadius));
	}
Begin:
	SwitchToBestWeapon();
	WaitForLanding();
	if( !bGuardPosition )
		WhatToDoNext(243);
	
	if( CloseEnough() )
	{
		Focus = None;
		FocalPoint = Pawn.Location+VRand()*800.f;
		NearWall(MINVIEWDIST);
		Pawn.Acceleration = vect(0,0,0);
		Sleep(0.5+FRand());
	}
	else if( PointReachable(GuardingPosition) )
		MoveTo(GuardingPosition,FaceActor(1));
	else
	{
		if( FindBestPathTo(GuardingPosition) )
			MoveToward(MoveTarget,FaceActor(1),GetDesiredOffset(),ShouldStrafeTo(MoveTarget));
		else bGuardPosition = false;
	}
	WhatToDoNext(245);
	if ( bSoaking )
		SoakStop("STUCK IN GUARDING!");
}

final function bool FarFromObjective()
{
	if( AssistingPlayer!=None && AssistingPlayer.Pawn!=None && (VSizeSquared(AssistingPlayer.Pawn.Location-Pawn.Location)>250000.f 
	|| !LineOfSightTo(AssistingPlayer.Pawn)) )
		return true;
	if( bGuardPosition && VSizeSquared(GuardingPosition-Pawn.Location)>250000.f )
		return true;
	return false;
}
final function bool SetObjectiveMove()
{
	if( FarFromObjective() )
	{
		if( AssistingPlayer!=None && AssistingPlayer.Pawn!=None )
		{
			if( ActorReachable(AssistingPlayer.Pawn) )
			{
				Destination = PickAssistOffset(AssistingPlayer.Pawn);
				return true;
			}
			if( FindBestPathToward(AssistingPlayer.Pawn,true,false) )
				return true;
		}
		if( bGuardPosition )
		{
			if( PointReachable(GuardingPosition) )
			{
				Destination = GuardingPosition;
				return true;
			}
			MoveTarget = FindPathTo(GuardingPosition);
			if( MoveTarget!=None )
				return true;
		}
	}
	return false;
}
function WanderOrCamp(bool bMayCrouch)
{
	Pawn.bWantsToCrouch = false;
	if( !FindRoamDest() )
		GotoState('RestFormation');
}
function DirectedWander(vector WanderDir)
{
	Pawn.bWantsToCrouch = false;
	if( !FindRoamDest() )
		Super.DirectedWander(WanderDir);
}

state RangedAttack
{
	final function PickMoveDest()
	{
		local bool bScary;
		
		bScary = EnemyReallyScary();
		if ( (Pawn.Weapon != None) && Pawn.Weapon.bMeleeWeapon && !bScary )
		{
			MoveTarget = Target;
			return;
		}
		if( SetObjectiveMove() )
			return;
		if( bScary )
			PickNextRetMove();
		Destination = Pawn.Location+VRand()*200.f;
	}
Begin:
	bHasFired = false;
	if ( (Pawn.Weapon != None) && Pawn.Weapon.bMeleeWeapon )
		SwitchToBestWeapon();
	GoalString = GoalString@"Ranged attack";
	Focus = Target;
	Sleep(0.0);
	if ( Target == None )
		WhatToDoNext(335);

	Pawn.bWantsToCrouch = false;
	if ( NeedToTurn(Target.Location) )
	{
		Focus = Target;
		FinishRotation();
	}
	bHasFired = true;
	if ( Target == Enemy )
		TimedFireWeaponAtEnemy();
	else
		FireWeaponAt(Target);
	Sleep(0.1);
	if ( (Target == None) || ((Target != Enemy) && (GameObjective(Target) == None) && (Enemy != None) && EnemyVisible()) )
		WhatToDoNext(35);
	Focus = Target;
	PickMoveDest();
	if( MoveTarget!=None )
		MoveToward(MoveTarget,Target);
	else MoveTo(Destination,Target);
	
	WhatToDoNext(36);
	if ( bSoaking )
		SoakStop("STUCK IN RANGEDATTACK!");
}

state TacticalMove
{
ignores SeePlayer, HearNoise;

	function DoTacticalMove()
	{
		TimedFireWeaponAtEnemy();
		GotoState('TacticalMove','Begin');
	}
	function EnemyNotVisible()
	{
		StopFiring();
		if( FarFromObjective() ) // Ignore enemy for now.
		{
			Enemy = None;
			WhatToDoNext(20);
			return;
		}
		if ( aggressiveness > relativestrength(enemy) )
		{
			if ( FastTrace(Enemy.Location, LastSeeingPos) )
				GotoState('TacticalMove','RecoverEnemy');
			else
				WhatToDoNext(20);
		}
		Disable('EnemyNotVisible');
	}
	function Timer()
	{
		enable('NotifyBump');
		TimedFireWeaponAtEnemy();
	}
	event NotifyJumpApex()
	{
		if ( bTacticalDoubleJump && !bPendingDoubleJump && (FRand() < 0.4) && (Skill > 2 + 5 * FRand()) )
		{
			bTacticalDoubleJump = false;
			bNotifyApex = true;
			bPendingDoubleJump = true;
		}
		else TimedFireWeaponAtEnemy();
		Global.NotifyJumpApex();
	}
	function PickDestination()
	{
		local vector pickdir, enemydir, enemyPart, Y;
		local float strafeSize;

		if ( Pawn == None )
		{
			warn(self$" Tactical move pick destination with no pawn");
			return;
		}
		bChangeDir = false;
		if ( Pawn.PhysicsVolume.bWaterVolume && !Pawn.bCanSwim && Pawn.bCanFly)
		{
			Destination = Pawn.Location + 75 * (VRand() + vect(0,0,1));
			Destination.Z += 100;
			return;
		}
		if( SetObjectiveMove() )
			return;

		enemydir = Normal(Enemy.Location - Pawn.Location);
		Y = (enemydir Cross vect(0,0,1));
		if ( Pawn.Physics == PHYS_Walking )
		{
			Y.Z = 0;
			enemydir.Z = 0;
		}
		else
			enemydir.Z = FMax(0,enemydir.Z);
		
		if( Pawn.Weapon!=None && !Pawn.Weapon.bMeleeWeapon && VSizeSquared(Enemy.Location-Pawn.Location)<360000.f ) // Back off if enemy is closer than 600
		{
			if ( EngageDirection(-enemydir, false) )
				return;
		}

		strafeSize = FClamp(((2 * Aggression + 1) * FRand() - 0.65),-0.7,0.7);
		if ( Squad.MustKeepEnemy(Enemy) )
			strafeSize = FMax(0.4 * FRand() - 0.2,strafeSize);

		enemyPart = enemydir * strafeSize;
		strafeSize = FMax(0.0, 1 - Abs(strafeSize));
		pickdir = strafeSize * Y;
		if ( bStrafeDir )
			pickdir *= -1;

		bStrafeDir = !bStrafeDir;

		if ( EngageDirection(enemyPart + pickdir, false) )
			return;

		if ( EngageDirection(enemyPart - pickdir,false) )
			return;

		bForcedDirection = true;
		StartTacticalTime = Level.TimeSeconds;
		EngageDirection(EnemyPart + PickDir, true);
	}

TacticalTick:
	Sleep(0.02);
Begin:
	if ( Enemy == None )
	{
		sleep(0.01);
		Goto('FinishedStrafe');
	}
	if (Pawn.Physics == PHYS_Falling)
	{
		Focus = Enemy;
		Destination = Enemy.Location;
		WaitForLanding();
	}
	if ( Enemy == None )
		Goto('FinishedStrafe');
	PickDestination();

DoMove:
	if( MoveTarget!=None )
		MoveToward(MoveTarget, Enemy);
	else if ( (Pawn.Weapon != None) && Pawn.Weapon.FocusOnLeader(false) )
		MoveTo(Destination, Focus);
	else if ( !Pawn.bCanStrafe )
	{
		StopFiring();
		MoveTo(Destination);
	}
	else
	{
DoStrafeMove:
		MoveTo(Destination, Enemy);
	}
	if ( bForcedDirection && (Level.TimeSeconds - StartTacticalTime < 0.2) )
	{
		if ( !Pawn.HasWeapon() || Skill > 2 + 3 * FRand() )
		{
			bMustCharge = true;
			WhatToDoNext(51);
		}
		GoalString = "RangedAttack from failed tactical";
		DoRangedAttackOn(Enemy);
	}
	if ( (Enemy == None) || EnemyVisible() || !FastTrace(Enemy.Location, LastSeeingPos) || (Pawn.Weapon != None && Pawn.Weapon.bMeleeWeapon) )
		Goto('FinishedStrafe');

RecoverEnemy:
	GoalString = "Recover Enemy";
	HidingSpot = Pawn.Location;
	StopFiring();
	Sleep(0.1 + 0.2 * FRand());
	Destination = LastSeeingPos + 4 * Pawn.CollisionRadius * Normal(LastSeeingPos - Pawn.Location);
	MoveTo(Destination, Enemy);

	if ( FireWeaponAt(Enemy) )
	{
		Pawn.Acceleration = vect(0,0,0);
		if ( (Pawn.Weapon != None) && Pawn.Weapon.SplashDamage() )
		{
			StopFiring();
			Sleep(0.05);
		}
		else
			Sleep(0.1 + 0.3 * FRand() + 0.06 * (7 - FMin(7,Skill)));
		if ( (FRand() + 0.3 > Aggression) )
		{
			Enable('EnemyNotVisible');
			Destination = HidingSpot + 4 * Pawn.CollisionRadius * Normal(HidingSpot - Pawn.Location);
			Goto('DoMove');
		}
	}
FinishedStrafe:
	WhatToDoNext(21);
	if ( bSoaking )
		SoakStop("STUCK IN TACTICAL MOVE!");
}

state Shopping
{
ignores EnemyNotVisible;

	function float RateWeapon(Weapon W)
	{
		if( KFWeapon(W)==None )
			return Global.RateWeapon(W);
		return FMax(10.f-KFWeapon(W).Weight,0.f)*0.75;
	}
	final function bool GetEntryMove()
	{
		local vector X;
		local byte i;
		
		X = ShopVolumeActor.Location-Pawn.Location;
		X.Z = 0;
		X = Normal(X);
		Destination = Pawn.Location;
		for( i=0; i<8; ++i )
		{
			Destination += X*(150.f+FRand()*50.f);
			if( !PointReachable(Destination) )
				return (i>0);
		}
		return true;
	}
Begin:
	WaitForLanding();
	AssignPersonality(); // Gain new personality on new wave.
	bHasChecked = False;
	SwitchToBestWeapon();

KeepMoving:
	if( DZ_GameType(Level.Game).bWaveInProgress )
	{
		LastShopTime = level.TimeSeconds+15+FRand()*30;
		WhatToDoNext(152);
	}
	if( ActorReachable(ShoppingPath) )
		MoveToward(ShoppingPath,ShopVolumeActor,,false);
	else if( FindBestPathToward(ShoppingPath,true,false) )
	{
		MoveToward(MoveTarget,FaceActor(1),,false );
		Goto('KeepMoving');
	}
	else
	{
		LastShopTime = level.TimeSeconds+8+FRand()*10;
		WhatToDoNext(151);
	}
	if( GetEntryMove() )
		MoveTo(Destination);
	Focus = ShopVolumeActor;
	Pawn.Acceleration = vect(0,0,0);
	Sleep(1+FRand()*3);
	DoTrading();
	Sleep(0.25);
	MoveToward(ShoppingPath,ShoppingPath,,false );
	WhatToDoNext(152);
	if ( bSoaking )
		SoakStop("STUCK IN SHOPPING!");
}
state NadeTarget
{
Ignores NotifyBump,SetEnemy;

	final function TossNade()
	{
		Target = Enemy;
		MyGrenades.ServerThrow();
	}
	function EndState()
	{
		if( KFPawn(Pawn)!=none )
			KFPawn(Pawn).bThrowingNade = false;
	}
Begin:
	Focus = Enemy;
	Sleep(0.1f);
	if( KFPawn(Pawn) != none )
		KFPawn(Pawn).HandleNadeThrowAnim();
	Sleep(0.2);
	TossNade();
	Sleep(0.4);
	WhatToDoNext(153);
	if ( bSoaking )
		SoakStop("STUCK IN NADES!");
}
state Roaming
{
ignores EnemyNotVisible;

	function float RateWeapon(Weapon W)
	{
// #ifdef WITH_SENTRY_BOT
		 if( W==MySentryGun )
		 {
			 if( !MySentryGun.bSentryDeployed ) // Deply it ASAP.
				 return 2.f;
			 return -2;
		 }
// #endif
		if( W==MyPipes && W.HasAmmo() )
			return 2.f;
		return Global.RateWeapon(W);
	}
	function Timer() // Drop pipes on ground while wandering.
	{
		SetCombatTimer();
		enable('NotifyBump');
		if( MyPipes!=None && Pawn.Weapon==MyPipes && !PipebombsNear() )
			MyPipes.BotFire(false);
// #ifdef WITH_SENTRY_BOT
		 if( MySentryGun!=None && !MySentryGun.bSentryDeployed && Pawn.Weapon==MySentryGun ) // Drop sentry now.
			 MySentryGun.ServerStartFire(0);
// #endif
	}
	final function bool PipebombsNear() // Make sure to not clunge all pipebombs together.
	{
		local Actor P;
		local class<Projectile> PC;
		
		PC = MyPipes.GetFireMode(0).ProjectileClass;
		if( PC!=None )
		{
			foreach CollidingActors(PC,P,120,Pawn.Location)
				return true;
		}
		return false;
	}
}
state StakeOut
{
ignores EnemyNotVisible;

	event SeePlayer(Pawn SeenPlayer)
	{
		if ( SeenPlayer == Enemy )
		{
			VisibleEnemy = Enemy;
			EnemyVisibilityTime = Level.TimeSeconds;
			bEnemyIsVisible = true;
			if ( ((Pawn.Weapon == None) || !Pawn.Weapon.FocusOnLeader(false)) && (FRand() < 0.5) )
			{
				Focus = Enemy;
				FireWeaponAt(Enemy);
			}
			WhatToDoNext(28);
		}
		else if ( SetEnemy(SeenPlayer) )
		{
			if ( Enemy == SeenPlayer )
			{
				VisibleEnemy = Enemy;
				EnemyVisibilityTime = Level.TimeSeconds;
				bEnemyIsVisible = true;
			}
			WhatToDoNext(29);
		}
	}
}

// #ifdef WITH_AMMO_BOX
 state GettingAmmo extends OrderMove
 {
	 function EnemyAquired()
	 {
		 if( !bHighPriorityAmmo && LineOfSightTo(Enemy) )
			 Global.EnemyAquired();
	 }
	 final function PickDestination()
	 {
		// DEBUGF("SeekAmmo"@SeekingAmmo);
		 if( ActorReachable(SeekingAmmo) )
		 {
			 MoveTarget = None;
			 Destination = SeekingAmmo.Location - Normal(SeekingAmmo.Location-Pawn.Location)*(SeekingAmmo.CollisionRadius+25.f);
			 return;
		 }
		 if( FindBestPathToward(SeekingAmmo,true,false) )
			 return;
		 SeekingAmmo = None;
		 NextAmmoCheckTime = Level.TimeSeconds + (5.f + FRand()*8.f);
		 WhatToDoNext(40);
	 }
	 function Timer()
	 {
		 if( SeekingAmmo==None || SeekingAmmo.Health<=0 || !DZ_GameType(Level.Game).bWaveInProgress )
		 {
			 if( bAmmoBoxInUse && SeekingAmmo!=None )
				 SeekingAmmo.UserStatus(false);
			 SeekingAmmo = None;
			 WhatToDoNext(38);
			 return;
		 }
		 if( !bAmmoBoxInUse && VSizeSquared(SeekingAmmo.Location-Pawn.Location)<Square(Pawn.CollisionRadius+SeekingAmmo.CollisionRadius+60.f) )
		 {
			 bAmmoBoxInUse = true;
			 SeekingAmmo.UserStatus(true);
			 GoToState(,'BuyAmmo');
		 }
	 }
	 function EndState()
	 {
		 Super.EndState();
		 if( bAmmoBoxInUse )
		 {
			 if( SeekingAmmo!=None )
				 SeekingAmmo.UserStatus(false);
			 bAmmoBoxInUse = false;
		 }
	 }
	 final function BoughtAmmo()
	 {
		 local float TotalRefund;
		 local Inventory I;
		 local Weapon W;
 
		 if( SeekingAmmo==None || SeekingAmmo.Health<=0 )
		 {
			 SeekingAmmo = None;
			 return;
		 }
		 
		 for( I=Pawn.Inventory; I!=None; I=I.Inventory )
		 {
			 W = Weapon(I);
			 if( W!=None && !W.bMeleeWeapon && W!=MyGrenades && W.GetAmmoClass(0)!=None && !W.AmmoMaxed(0) )
			 {
				 TotalRefund+=float(FillAllAmmo(W.GetAmmoClass(0),Class'AmmoBox'.Default.AmmoCostScale)) * Class'AmmoBox'.Default.MoneyRefundScale;
			 }
		 }
		 if( MyGrenades!=None && Rand(3)==0 && !MyGrenades.AmmoMaxed(0) )
			 TotalRefund+=float(FillAllAmmo(MyGrenades.GetAmmoClass(0),Class'AmmoBox'.Default.AmmoCostScale)) * Class'AmmoBox'.Default.MoneyRefundScale;
 
		 TotalRefund = int(TotalRefund);
		 if( TotalRefund>0 && SeekingAmmo.OwnerController!=None && SeekingAmmo.OwnerController.PlayerReplicationInfo!=None )
		 {
			 SeekingAmmo.OwnerController.PlayerReplicationInfo.Score+=TotalRefund;
			 SeekingAmmo.OwnerController.PlayerReplicationInfo.NetUpdateTime = Level.TimeSeconds - 1.f;
			 Spawn(Class'AmmoRefundMsg',SeekingAmmo.OwnerController,,Pawn.Location+(vect(0,0,1)*Pawn.CollisionHeight),rot(0,0,0)).TotalDosh = TotalRefund;
		 }
		 if( bAmmoBoxInUse )
			 SeekingAmmo.UserStatus(false);
		 bAmmoBoxInUse = false;
		 SeekingAmmo = None;
	 }
 
 Begin:
	 SetTimer(0.1,true);
	 WaitForLanding();
 
 KeepMoving:
	 while( !bAmmoBoxInUse )
	 {
		 if( SeekingAmmo==None || SeekingAmmo.Health<=0 )
		 {
			 SeekingAmmo = None;
			 WhatToDoNext(39);
		 }
		 PickDestination();
		 if( MoveTarget!=None )
			 MoveToward(MoveTarget,FaceActor(1),GetDesiredOffset(),ShouldStrafeTo(MoveTarget));
		 else MoveTo(Destination,SeekingAmmo);
	 }
 
 BuyAmmo:
	 MoveTimer = -1;
	 Pawn.Acceleration = vect(0,0,0);
	 Focus = SeekingAmmo;
	 Sleep(0.5+FRand()*2.f);
	 BoughtAmmo();
	 WhatToDoNext(41);
 }
// #endif

state WeldAssist
{
	function BeginState()
	{
		WeldAssistTimer = Level.TimeSeconds+6.f;
		SetTimer(0,false);
		StopFiring();
	}
	function EndState()
	{
		SetTimer(0.15,true);
		StopFiring();
	}
	function SwitchToBestWeapon()
	{
		if ( Pawn==None || Pawn.Inventory==None || Pawn.Weapon==ActiveWelder )
			return;
		Pawn.PendingWeapon = ActiveWelder;
		StopFiring();
		if ( Pawn.Weapon == None )
			Pawn.ChangedWeapon();
		else Pawn.Weapon.PutDown();
	}
	function Timer()
	{
		if( TargetDoor.bDoorIsDead )
		{
			WhatToDoNext(45);
			return;
		}
		if( (AssistWeldMode==1 && !TargetDoor.bSealed) || (AssistWeldMode==0 && TargetDoor.WeldStrength>=TargetDoor.MaxWeld) )
		{
			if( !TargetDoor.bSealed && TargetDoor.MyTrigger!=None )
				TargetDoor.MyTrigger.UsedBy(Pawn); // Make bot open door once unwelding is finished.
			WhatToDoNext(46);
			return;
		}
		if( Pawn.Weapon==ActiveWelder )
		{
			Target = TargetDoor;
			ActiveWelder.StartFire(AssistWeldMode);
		}
		else SwitchToBestWeapon();
	}
	function bool NotifyHitWall(vector HitNormal, actor Wall)
	{
		if( Wall==TargetDoor )
		{
			GoToState(,'WeldDoor');
			SetTimer(0.15,true);
		}
		return true;
	}
	function bool WeaponFireAgain(float RefireRate, bool bFinishedFire)
	{
		if( Pawn.Weapon!=ActiveWelder )
		{
			StopFiring();
			return false;
		}
		return true; // Keep welding.
	}
Begin:
	SwitchToBestWeapon();
	MoveToward(TargetDoor);
	WhatToDoNext(43);
WeldDoor:
	WeldAssistTimer = Level.TimeSeconds+12.f;
	Pawn.Acceleration = vect(0,0,0);
	Sleep(10.f);
	WhatToDoNext(44);
}

defaultproperties
{
	     PawnClass=Class'SRHumanPawn'

}
