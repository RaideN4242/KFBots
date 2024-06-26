//-----------------------------------------------------------
//
//-----------------------------------------------------------
class KFBotLevelRules extends ReplicationInfo
    config
	placeable;

const       MAX_CATEGORY        = 5;
const       MAX_BUYITEMS        = 63;

struct EquipmentCategory
{
	var    byte    EquipmentCategoryID;
	var    string  EquipmentCategoryName;
};

var()       EquipmentCategory   EquipmentCategories[MAX_CATEGORY];
//var(Shop)   class<Pickup>       ItemForSale[MAX_BUYITEMS];
var         array< class<Pickup> >      ItemForSale;

var(Shop)   array< class<Pickup> >      MediItemForSale;
var(Shop)   array< class<Pickup> >      SuppItemForSale;
var(Shop)   array< class<Pickup> >      ShrpItemForSale;
var(Shop)   array< class<Pickup> >      CommItemForSale;
var(Shop)   array< class<Pickup> >      BersItemForSale;
var(Shop)   array< class<Pickup> >      FireItemForSale;
var(Shop)   array< class<Pickup> >      DemoItemForSale;
var(Shop)   array< class<Pickup> >      AssItemForSale;
var(Shop)   array< class<Pickup> >      FigItemForSale;
var(Shop)   array< class<Pickup> >      VIPItemForSale;
var(Shop)   array< class<Pickup> >      NeutItemForSale;

var globalconfig  array< class<Pickup> >      FaveItemForSale;

var() float WaveSpawnPeriod;

simulated function bool IsFavorited( class<Pickup> Item )
{
    local int i;

    for( i = 0; i < FaveItemForSale.Length; ++i )
    {
        if( Item == FaveItemForSale[i] )
        {
            return true;
        }
    }

    return false;
}

simulated function AddToFavorites( class<Pickup> Item )
{
    local class<KFWeaponPickup> WeaponPickupClass;

    WeaponPickupClass = class<KFWeaponPickup>( Item );
    if( WeaponPickupClass != none )
    {
        FaveItemForSale[ FaveItemForSale.Length ] = WeaponPickupClass;
        SaveFavorites();
    }
}

simulated function RemoveFromFavorites( class<Pickup> Item )
{
    local int i;

    for( i = 0; i < FaveItemForSale.Length; ++i )
    {
        if( Item == FaveItemForSale[i] )
        {
            FaveItemForSale.Remove(i, 1);
            break;
        }
    }

    SaveFavorites();
}

simulated function SaveFavorites()
{
    SaveConfig();
}

defaultproperties
{
     EquipmentCategories(0)=(EquipmentCategoryName="Melee")
     EquipmentCategories(1)=(EquipmentCategoryID=1,EquipmentCategoryName="Secondary")
     EquipmentCategories(2)=(EquipmentCategoryID=2,EquipmentCategoryName="Primary")
     EquipmentCategories(3)=(EquipmentCategoryID=3,EquipmentCategoryName="Specials")
     EquipmentCategories(4)=(EquipmentCategoryID=4,EquipmentCategoryName="Equipment")
     MediItemForSale(0)=Class'M7A3MPickupQ'
     MediItemForSale(1)=Class'M7A3MPickup_DZ'
     MediItemForSale(2)=Class'KevlarBombPickup'
     MediItemForSale(3)=Class'M56PickupU'
     MediItemForSale(4)=Class'MedicBombPickup'
     SuppItemForSale(0)=Class'ServerPErksDZ.ultimaxGALAutoShotgun'
     SuppItemForSale(1)=Class'DZWeaponPack.ProtectaPickup'
     SuppItemForSale(2)=Class'DZWeaponPack.Saiga12cPickupT'
     SuppItemForSale(3)=Class'ServerPErksDZ.W1300_Compact_Edition'
     SuppItemForSale(4)=Class'DZWeaponPack.Rem870ECPickup'
     SuppItemForSale(5)=Class'DZWeaponPack.MTS255Pickup'
     SuppItemForSale(6)=Class'ServerPerksDZ.AA12AutoShotgunU'
     SuppItemForSale(7)=Class'ServerPErksDZ.WTFEquipAFS14PickupB'
     SuppItemForSale(8)=Class'ServerPerksDZ.GoldenBenelliPickupDZ'
     SuppItemForSale(9)=Class'ServerPerksDZ.AA12DWPickup'
     SuppItemForSale(10)=Class'DZWeaponPack.Saiga12cPickup'
     SuppItemForSale(11)=Class'DZWeaponPack.USAS12_V2Pickup'
     SuppItemForSale(12)=Class'ServerPerksDZ.Saiga12SAPickup'
     SuppItemForSale(13)=Class'ServerPerksDZ.SPAS12Pickup'
     SuppItemForSale(14)=Class'ServerPerksDZ.WTFEquipAFS12Pickup'
     SuppItemForSale(15)=Class'ServerPerksDZ.HaymakerPickup'
     SuppItemForSale(16)=Class'ServerPerksDZ.SentryGunPickup'
     ShrpItemForSale(0)=Class'ServerPerksDZ.SentryGunPickup'
     ShrpItemForSale(1)=Class'ServerPerksDZ.DesertEagleLLIPickup'
     ShrpItemForSale(2)=Class'ServerPerksDZ.M44Pickup'
     ShrpItemForSale(3)=Class'KFMod.Magnum44Pickup'
     ShrpItemForSale(4)=Class'ServerPerksDZ.L96AWPLLIPickup_P'
     ShrpItemForSale(5)=Class'ServerPerksDZ.L115A3SAPickup'
     ShrpItemForSale(6)=Class'KFMod.MK23Pickup'
     ShrpItemForSale(7)=Class'ServerPerksDZ.Jacalv2Pickup'
     ShrpItemForSale(8)=Class'ServerPerksDZ.M82A1LLIPickup'
     ShrpItemForSale(9)=Class'ServerPerksDZ.AwmDragonLLIPickup'
     ShrpItemForSale(10)=Class'ServerPerksDZ.M99Pickup'
     ShrpItemForSale(11)=Class'ServerPerksDZ.M39EBRPickup'
     ShrpItemForSale(12)=Class'ServerPerksDZ.GaussSAPickup'
     ShrpItemForSale(13)=Class'ServerPerksDZ.L96AWPLLIPickup'
     ShrpItemForSale(14)=Class'ServerPerksDZ.DesertEagleLLIPickup'
     CommItemForSale(0)=Class'ServerPerksDZ.FamasG2LLIPickupP'
     CommItemForSale(1)=Class'ServerPerksDZ.GalilComicSAAssaultRifle'
     CommItemForSale(2)=Class'ServerPerksDZ.StunM79Pickup'
     CommItemForSale(3)=Class'ServerPerksDZ.PKMPickup'
     CommItemForSale(4)=Class'ServerPerksDZ.G36StalkerPickup'
     CommItemForSale(5)=Class'ServerPerksDZ.WTFEquipSCAR19Pickup'
     CommItemForSale(6)=Class'ServerPerksDZ.SCARPROFPickup'
     CommItemForSale(7)=Class'ServerPerksDZ.PatGunPickup'
     CommItemForSale(8)=Class'DZWeaponPack.VALDTPickup'
     CommItemForSale(9)=Class'ServerPerksDZ.ScarHSAPickupU'
     CommItemForSale(10)=Class'ServerPerksDZ.P90SAPickup'
     CommItemForSale(11)=Class'DZWeaponPack.RifAugA3SAPickup'
     CommItemForSale(12)=Class'GalilSAPickup'
     BersItemForSale(0)=Class'AxeEbonitePickup'
     BersItemForSale(1)=Class'ServerPerksDZ.AxePickup'
     BersItemForSale(2)=Class'PenetratorPickup'
     BersItemForSale(3)=Class'WTFEquipFireAxePickup'
     BersItemForSale(4)=Class'HalberdPickupBilly'
     BersItemForSale(5)=Class'BBatPickup'
     BersItemForSale(6)=Class'LightsaberPickup'
 //    BersItemForSale(7)=Class'LightsaberPickup'
//     BersItemForSale(8)=Class'KFMod.DwarfAxePickup'
//     BersItemForSale(9)=Class'ServerPerksDZ.AxeEbonitePickup'
//     BersItemForSale(10)=Class'KFMod.CrossbuzzsawPickup'
//	 BersItemForSale=(11)=Class'ServerPerksDZ.AxeEbonitePickup'
//	 BersItemForSale=(12)=Class'ServerPErksDZ.KatanaSAPickup'
//	 BersItemForSale=(13)=Class'ServerPErksDZ.HalberdPickup'
//	 BersItemForSale=(14)=Class'ServerPErksDZ.WTFEquipFireAxePickup'
//	 BersItemForSale=(15)=Class'ServerPErksDZ.LightsaberPickup'
     FireItemForSale(0)=Class'QHuskGunPickup'
     FireItemForSale(1)=Class'WTFEquipFTPickup'
     FireItemForSale(2)=Class'PlasmaTrenchgunPickup'
     FireItemForSale(3)=Class'XM8PickupU'
     FireItemForSale(4)=Class'WTFEquipM79CFPickup'
     FireItemForSale(5)=Class'PatGunPickup'
     FireItemForSale(6)=Class'MAC10PickupKr'
     FireItemForSale(7)=Class'HopMineLPickup'
     DemoItemForSale(0)=Class'ExplosiveAA12Pickup'
     DemoItemForSale(1)=Class'GLA87PickupU'
     DemoItemForSale(2)=Class'HopMineLPickup'
     DemoItemForSale(3)=Class'RG6GLPickup'
     DemoItemForSale(4)=Class'SeekerDZSixPickup'
     DemoItemForSale(5)=Class'EX41Pickup'
     DemoItemForSale(6)=Class'RPGPickupp'
//     DemoItemForSale(7)=Class'KFMod.LAWPickup'
//     DemoItemForSale(8)=Class'KFMod.M32Pickup'
//     DemoItemForSale(9)=Class'KFMod.CamoM32Pickup'
     AssItemForSale(0)=Class'DualColtPickup'
     AssItemForSale(1)=Class'DuallKrissPickupBoss'
     AssItemForSale(2)=Class'DualNew_Glock17Pickup'
     AssItemForSale(3)=Class'DualSW500GPickup'
     AssItemForSale(4)=Class'DualTmpPickup'
     AssItemForSale(5)=Class'DualTmpPickup_SHKET'
     AssItemForSale(6)=Class'SentryGunPickup'
     AssItemForSale(7)=Class'Jacalv2Pickup'
     FigItemForSale(0)=Class'AXBowPickup'
     FigItemForSale(1)=Class'StingerPickup'
     FigItemForSale(2)=Class'EvoProSAPickup'
     FigItemForSale(3)=Class'A909Pickup'
     FigItemForSale(4)=Class'XM8Pickup_Kratos'
     FigItemForSale(5)=Class'AK47PickupFighter'
     FigItemForSale(6)=Class'AXBowAmmoPickup_Stig'
     FigItemForSale(7)=Class'SRS900Pickup'
     FigItemForSale(8)=Class'M925Pickup'
     VIPItemForSale(0)=Class'M925Pickup'
     VIPItemForSale(1)=Class'ExplosiveAA12Pickup'
     VIPItemForSale(2)=Class'AA12DWPickup'
     VIPItemForSale(3)=Class'AA12DWPickup'
     VIPItemForSale(4)=Class'ultimaxGALAutoShotgun'
     VIPItemForSale(5)=Class'HopMineLPickup'
     VIPItemForSale(6)=Class'SRS900Pickup'
     VIPItemForSale(7)=Class'DualTmpPickup_SHKET'
     WaveSpawnPeriod=2.000000
}
