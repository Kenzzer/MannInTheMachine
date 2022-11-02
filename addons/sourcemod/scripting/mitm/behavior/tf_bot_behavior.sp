/**
 * Copyright (C) 2022  Mikusch
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#pragma semicolon 1
#pragma newdecls required

static NextBotActionFactory ActionFactory;

methodmap CTFBotMainAction < NextBotAction
{
	public static void Init()
	{
		ActionFactory = new NextBotActionFactory("MainAction");
		ActionFactory.BeginDataMapDesc()
			.DefineIntField("m_undergroundTimer")
		.EndDataMapDesc();
		ActionFactory.SetCallback(NextBotActionCallbackType_InitialContainedAction, InitialContainedAction);
		ActionFactory.SetCallback(NextBotActionCallbackType_OnStart, OnStart);
		ActionFactory.SetCallback(NextBotActionCallbackType_Update, Update);
		ActionFactory.SetCallback(NextBotActionCallbackType_OnEnd, OnEnd);
		ActionFactory.SetCallback(NextBotActionCallbackType_CreateInitialAction, CreateInitialAction);
		ActionFactory.SetEventCallback(EventResponderType_OnKilled, OnKilled);
		ActionFactory.SetEventCallback(EventResponderType_OnContact, OnContact);
		ActionFactory.SetEventCallback(EventResponderType_OnOtherKilled, OnOtherKilled);
	}
	
	public static NextBotActionFactory GetFactory()
	{
		return ActionFactory;
	}
	
	public CTFBotMainAction()
	{
		return view_as<CTFBotMainAction>(ActionFactory.Create());
	}
	
	property IntervalTimer m_undergroundTimer
	{
		public get()
		{
			return this.GetData("m_undergroundTimer");
		}
		public set(IntervalTimer undergroundTimer)
		{
			this.SetData("m_undergroundTimer", undergroundTimer);
		}
	}
}

static NextBotAction InitialContainedAction(CTFBotMainAction action, int actor)
{
	if (TF2_GetClientTeam(actor) == TFTeam_Invaders)
	{
		return CTFBotScenarioMonitor();
	}
	
	return NULL_ACTION;
}

static int OnStart(CTFBotMainAction action, int actor, NextBotAction priorAction)
{
	// if bot is already dead at this point, make sure it's dead
	// check for !IsAlive because bot could be DYING
	if (!IsPlayerAlive(actor))
	{
		return action.ChangeTo(CTFBotDead(), "I'm actually dead");
	}
	
	// must leave spawn area
	Player(actor).m_flSpawnTimeLeft = Player(actor).CalculateSpawnTime();
	
	return action.Continue();
}

static int Update(CTFBotMainAction action, int actor, float interval)
{
	if (TF2_GetClientTeam(actor) != TFTeam_Invaders)
	{
		// not an invader - do nothing
		return action.Done("Not an invader");
	}
	
	if (IsMannVsMachineMode() && TF2_GetClientTeam(actor) == TFTeam_Invaders)
	{
		CTFNavArea myArea = view_as<CTFNavArea>(CBaseCombatCharacter(actor).GetLastKnownArea());
		TFNavAttributeType spawnRoomFlag = TF2_GetClientTeam(actor) == TFTeam_Red ? RED_SPAWN_ROOM : BLUE_SPAWN_ROOM;
		
		if (myArea && myArea.HasAttributeTF(spawnRoomFlag))
		{
			// invading bots get uber while they leave their spawn so they don't drop their cash where players can't pick it up
			TF2_AddCondition(actor, TFCond_Ubercharged, 0.5);
			TF2_AddCondition(actor, TFCond_UberchargedHidden, 0.5);
			TF2_AddCondition(actor, TFCond_UberchargeFading, 0.5);
			
			// force bots to walk out of spawn
			if (!Player(actor).HasAttribute(AUTO_JUMP))
			{
				TF2Attrib_SetByName(actor, "no_jump", 1.0);
			}
			
			// pause spawn timer while stunned
			if (!TF2_IsPlayerInCondition(actor, TFCond_Dazed))
			{
				Player(actor).m_flSpawnTimeLeft -= interval;
				
				if (Player(actor).m_flSpawnTimeLeft <= 0.0)
				{
					ForcePlayerSuicide(actor);
				}
			}
			
			// pressure them to leave the spawn area
			if (Player(actor).m_flSpawnTimeLeft > 0.0)
			{
				SetHudTextParams(-1.0, 0.7, interval, 255, 255, 255, 255);
				ShowSyncHudText(actor, g_WarningHudSync, "%t", "Invader_HurryOutOfSpawn", Player(actor).m_flSpawnTimeLeft);
			}
		}
		else
		{
			TF2Attrib_RemoveByName(actor, "no_jump");
		}
		
		float origin[3];
		GetClientAbsOrigin(actor, origin);
		
		// watch for bots that have fallen through the ground
		if (myArea && myArea.GetZVector(origin) - origin[2] > 100.0)
		{
			if (!action.m_undergroundTimer.HasStarted())
			{
				action.m_undergroundTimer.Start();
			}
			else if (action.m_undergroundTimer.IsGreaterThan(3.0))
			{
				char auth[MAX_AUTHID_LENGTH], teamName[MAX_TEAM_NAME_LENGTH];
				GetClientAuthId(actor, AuthId_Engine, auth, sizeof(auth), false);
				GetTeamName(GetClientTeam(actor), teamName, sizeof(teamName));
				
				LogMessage("\"%N<%i><%s><%s>\" underground (position \"%3.2f %3.2f %3.2f\")",
						   actor,
						   GetClientUserId(actor),
						   auth,
						   teamName,
						   origin[0], origin[1], origin[2]);
				
				// teleport bot to a reasonable place
				float center[3];
				myArea.GetCenter(center);
				TeleportEntity(actor, center);
			}
		}
		else
		{
			action.m_undergroundTimer.Invalidate();
		}
	}
	
	return action.Continue();
}

static void OnEnd(CTFBotMainAction action, int actor, NextBotAction nextAction)
{
	delete action.m_undergroundTimer;
}

static void CreateInitialAction(CTFBotMainAction action)
{
	action.m_undergroundTimer = new IntervalTimer();
}

static int OnKilled(CTFBotMainAction action, int actor, int attacker, int inflictor, float damage, int damagetype)
{
	return action.TryChangeTo(CTFBotDead(), RESULT_CRITICAL, "I died!");
}

static int OnContact(CTFBotMainAction action, int actor, int other, Address result)
{
	if (IsValidEntity(other) && !(view_as<SolidFlags_t>(GetEntProp(other, Prop_Data, "m_usSolidFlags")) & FSOLID_NOT_SOLID) && other != 0 && !IsEntityClient(other))
	{
		// Mini-bosses destroy non-Sentrygun objects they bump into (ie: Dispensers)
		if (IsMannVsMachineMode() && Player(actor).IsMiniBoss())
		{
			if (IsBaseObject(other))
			{
				if (TF2_GetObjectType(other) != TFObject_Sentry || GetEntProp(other, Prop_Send, "m_bMiniBuilding"))
				{
					int damage = Max(GetEntProp(other, Prop_Data, "m_iMaxHealth"), GetEntProp(other, Prop_Data, "m_iHealth"));
					
					float victimCenter[3], actorCenter[3], toVictim[3];
					CBaseEntity(other).WorldSpaceCenter(victimCenter);
					CBaseEntity(actor).WorldSpaceCenter(actorCenter);
					SubtractVectors(victimCenter, actorCenter, toVictim);
					
					float vecForce[3];
					CalculateMeleeDamageForce(toVictim, float(4 * damage), 1.0, vecForce);
					SDKHooks_TakeDamage(other, actor, actor, float(4 * damage), DMG_BLAST, _, vecForce, actorCenter);
				}
			}
		}
	}
	
	return action.TryContinue();
}

static int OnOtherKilled(CTFBotMainAction action, int actor, int victim, int attacker, int inflictor, float damage, int damagetype)
{
	bool do_taunt = IsEntityClient(victim);
	
	if (do_taunt)
	{
		if (TF2_GetClientTeam(actor) != TF2_GetClientTeam(victim) && actor == attacker)
		{
			bool isTaunting = !HasTheFlag(attacker) && GetRandomFloat(0.0, 100.0) <= tf_bot_taunt_victim_chance.FloatValue;
			
			if (Player(attacker).IsMiniBoss())
			{
				// Bosses don't taunt puny humans
				isTaunting = false;
			}
			
			if (isTaunting)
			{
				// we just killed a human - taunt!
				return action.TrySuspendFor(CTFBotTaunt(), RESULT_IMPORTANT, "Taunting our victim");
			}
		}
	}
	
	return action.TryContinue();
}
