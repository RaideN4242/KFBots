class FIX_KatanaFire extends KatanaFire;

function Timer()
{
	ProcessFire(Self);
}
static final function vector GetAimPos( Actor Other )
{
	local KFMonster P;
	local Coords C;
	local bool bAlt;

	P = KFMonster(Other);
	if( P==None || P.Health<=0 )
		return Other.Location;
	if( P.HeadBone=='' || SkeletalMesh(P.Mesh)==None )
		return P.Location + vect(0,0,0.9)*P.CollisionHeight;
	
	// If we are a dedicated server estimate what animation is most likely playing on the client
	if( P.Level.NetMode == NM_DedicatedServer )
	{
		if( !P.IsAnimating(0) && !P.IsAnimating(1) )
		{
			if (P.Physics == PHYS_Falling)
				P.PlayAnim(P.AirAnims[0], 1.0, 0.0);
			else if (P.Physics == PHYS_Walking)
			{
				if (P.bIsCrouched)
					P.PlayAnim(P.IdleCrouchAnim, 1.0, 0.0);
				else bAlt=true;
			}
			else if (P.Physics == PHYS_Swimming)
				P.PlayAnim(P.SwimAnims[0], 1.0, 0.0);

			P.SetAnimFrame(0.5);
		}
	}

	if( bAlt )
		return P.Location + (P.OnlineHeadshotOffset >> P.Rotation);

	C = P.GetBoneCoords(P.HeadBone);
	return C.Origin + (P.HeadHeight * P.HeadScale * C.XAxis);
}
static final function function ProcessFire( KFMeleeFire F )
{
	local Actor HitActor;
	local vector StartTrace, EndTrace, HitLocation, HitNormal;
	local rotator PointRot;
	local int MyDamage;
	local bool bBackStabbed;
	local Pawn Victims;
	local vector dir, lookdir;
	local float DiffAngle, VictimDist;
	local Pawn Inst;

	MyDamage = F.MeleeDamage;

	If( F.Weapon!=None && F.Instigator!=None && !KFWeapon(F.Weapon).bNoHit )
	{
		Inst = F.Instigator;
		MyDamage = F.MeleeDamage;
		StartTrace = Inst.Location + Inst.EyePosition();

		if( Inst.Controller!=None && !Inst.IsHumanControlled() && Inst.Controller.Target!=None )
		{
        	PointRot = rotator(GetAimPos(Inst.Controller.Target)-StartTrace); // Give aimbot for bots.
        }
		else
        {
            PointRot = Inst.GetViewRotation();
        }

		EndTrace = StartTrace + vector(PointRot)*F.weaponRange;
		HitActor = Inst.Trace( HitLocation, HitNormal, EndTrace, StartTrace, true);

		if (HitActor!=None)
		{
			F.ImpactShakeView();

			if( HitActor.IsA('ExtendedZCollision') && HitActor.Base!=none && HitActor.Base.IsA('KFMonster') )
            {
                HitActor = HitActor.Base;
            }

			if ( (HitActor.IsA('KFMonster') || HitActor.IsA('KFHumanPawn')) && KFMeleeGun(F.Weapon).BloodyMaterial!=none )
			{
				F.Weapon.Skins[KFMeleeGun(F.Weapon).BloodSkinSwitchArray] = KFMeleeGun(F.Weapon).BloodyMaterial;
				F.Weapon.texture = F.Weapon.default.Texture;
			}
			if( F.Level.NetMode==NM_Client )
                Return;

			if( HitActor.IsA('Pawn') && !HitActor.IsA('Vehicle') && ((HitActor.Location-Inst.Location) dot vector(HitActor.Rotation))>0 ) // Fixed in Balance Round 2
			{
				bBackStabbed = true;
				MyDamage*=2; // Backstab >:P
			}

			if( (KFMonster(HitActor)!=none) )
			{
				KFMonster(HitActor).bBackstabbed = bBackStabbed;

                HitActor.TakeDamage(MyDamage, Inst, HitLocation, vector(PointRot), F.hitDamageClass);

            	if(F.MeleeHitSounds.Length > 0)
            	{
            		F.Weapon.PlaySound(F.MeleeHitSounds[Rand(F.MeleeHitSounds.length)],SLOT_None,F.MeleeHitVolume,,,,false);
            	}

				if( VSize(Inst.Velocity)>300 && KFMonster(HitActor).Mass<=Inst.Mass )
				    KFMonster(HitActor).FlipOver();
			}
			else
			{
				HitActor.TakeDamage(MyDamage, Inst, HitLocation, vector(PointRot), F.hitDamageClass);
				F.Level.Spawn(F.HitEffectClass,,, HitLocation, rotator(HitLocation - StartTrace));
			}
		}

		if( F.Weapon!=None && F.WideDamageMinHitAngle > 0 )
		{
            foreach F.Weapon.VisibleCollidingActors( class 'Pawn', Victims, (F.weaponRange * 3), StartTrace ) //, RadiusHitLocation
    		{
                if( Victims==HitActor || Victims.Health<=0 || Victims==Inst )
                    continue;

				VictimDist = VSizeSquared(Inst.Location - Victims.Location);

				if( VictimDist > (((F.weaponRange * 1.1) * (F.weaponRange * 1.1)) + (Victims.CollisionRadius * Victims.CollisionRadius)) )
					continue;

				lookdir = Normal(Vector(Inst.GetViewRotation()));
				dir = Normal(Victims.Location - Inst.Location);

				DiffAngle = lookdir dot dir;

				if( DiffAngle > F.WideDamageMinHitAngle )
				{
					Victims.TakeDamage(MyDamage*DiffAngle, Inst, (Victims.Location + Victims.CollisionHeight * vect(0,0,0.7)), vector(PointRot), F.hitDamageClass);
					if( F.Weapon==None )
						break;

					if( Victims!=None && F.MeleeHitSounds.Length>0 )
						Victims.PlaySound(F.MeleeHitSounds[Rand(F.MeleeHitSounds.length)],SLOT_None,F.MeleeHitVolume,,,,false);
				}
    		}
		}
	}
}

defaultproperties
{
}
