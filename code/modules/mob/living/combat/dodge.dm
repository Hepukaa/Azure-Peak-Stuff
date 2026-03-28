/mob/living/proc/attempt_dodge(datum/intent/intenty, mob/living/user)
	if(pulledby || pulling)
		return FALSE
	if(world.time < last_dodge + dodgetime)
		if(!istype(rmb_intent, /datum/rmb_intent/riposte))
			return FALSE
	if(has_status_effect(/datum/status_effect/debuff/riposted))
		return FALSE
	if(has_status_effect(/datum/status_effect/debuff/exposed) || has_status_effect(/datum/status_effect/debuff/vulnerable))
		return FALSE
	last_dodge = world.time
	if(src.loc == user.loc)
		return FALSE
	if(intenty)
		if(!intenty.candodge)
			return FALSE
	if(HAS_TRAIT(src, TRAIT_NODEF))
		return FALSE
	if(candodge)
		var/list/dirry = list()
		var/dx = x - user.x
		var/dy = y - user.y
		if(abs(dx) < abs(dy))
			if(dy > 0)
				dirry += NORTH
				dirry += WEST
				dirry += EAST
			else
				dirry += SOUTH
				dirry += WEST
				dirry += EAST
		else
			if(dx > 0)
				dirry += EAST
				dirry += SOUTH
				dirry += NORTH
			else
				dirry += WEST
				dirry += NORTH
				dirry += SOUTH
		var/turf/turfy
		if(fixedeye)
			var/dodgedir = turn(dir, 180)
			var/turf/turfcheck = get_step(src, dodgedir)
			if(turfcheck && !turfcheck.density)
				turfy = turfcheck
		if(!turfy)
			for(var/x in shuffle(dirry.Copy()))
				turfy = get_step(src,x)
				if(turfy)
					if(turfy.density)
						continue
					for(var/atom/movable/AM in turfy)
						if(AM.density)
							continue
					break
		if(pulledby)
			return FALSE
		if(!turfy)
			to_chat(src, span_boldwarning("There's nowhere to dodge to!"))
			return FALSE
		else
			var/dodge_result = do_dodge(user, turfy)
			if(dodge_result)
				flash_fullscreen("blackflash2")
				if(dodge_result != DODGE_PARTIAL)
					user.aftermiss()
				return dodge_result
			else
				return FALSE
	else
		return FALSE

// origin is used for multi-step dodges like jukes
/mob/living/proc/get_dodge_destinations(mob/living/attacker, atom/origin = src)
	var/dodge_dir = get_dir(attacker, origin)
	if(!dodge_dir) // dir is 0, so we're on the same tile.
		return null
	var/list/dirry = list(turn(dodge_dir, -90), dodge_dir, turn(dodge_dir, 90))
	// pick a random dir
	var/list/turf/dodge_candidates = list()
	for(var/dir_to_check in dirry)
		var/turf/dodge_candidate = get_step(origin, dir_to_check)
		if(!dodge_candidate)
			continue
		if(dodge_candidate.density)
			continue
		var/has_impassable_atom = FALSE
		for(var/atom/movable/AM in dodge_candidate)
			if(!AM.CanPass(src, dodge_candidate))
				has_impassable_atom = TRUE
				break
		if(has_impassable_atom)
			continue
		dodge_candidates += dodge_candidate
	return dodge_candidates

// Return values: FALSE = full hit, DODGE_PARTIAL = half damage, TRUE = full dodge
#define DODGE_PARTIAL 2

/mob/proc/do_dodge(mob/user, turf/turfy)
	if(dodgecd)
		return FALSE
	var/mob/living/L = src
	var/mob/living/U = user
	var/mob/living/carbon/human/H
	var/mob/living/carbon/human/UH
	var/obj/item/I
	var/drained = 10
	var/drained_npc = 5
	if(ishuman(src))
		H = src
	if(ishuman(user))
		UH = user
		I = UH.used_intent.masteritem
	var/prob2defend = U.defprob
	if(L.stamina >= L.max_stamina)
		return FALSE
	if(src.client)
		log_combat(src, user, "dodged against")
	if(L)
		if(H?.check_dodge_skill())
			prob2defend = prob2defend + (L.STASPD * 15)
		else
			prob2defend = prob2defend + (L.STASPD * 10)
	if(U)
		prob2defend = prob2defend - (U.STASPD * 10)
	if(I)
		if(I.wbalance == WBALANCE_SWIFT && U.STASPD > L.STASPD) //nme weapon is quick, so they get a bonus based on spddiff
			prob2defend = prob2defend - ( I.wbalance * ((U.STASPD - L.STASPD) * 10) )
		if(I.wbalance == WBALANCE_HEAVY && L.STASPD > U.STASPD) //nme weapon is slow, so its easier to dodge if we're faster
			prob2defend = prob2defend + ( I.wbalance * ((U.STASPD - L.STASPD) * 10) )
		prob2defend = prob2defend - (UH.get_skill_level(I.associated_skill) * 10)
	if(H)
		if(!H?.check_armor_skill() || H?.legcuffed)
			H.Knockdown(1)
			H.drop_all_held_items()
			to_chat(H, span_warning("I can't dodge in such unfitting armor! I'm knocked down!"))
			return FALSE
		if(I) //the enemy attacked us with a weapon
			if(!I.associated_skill) //the enemy weapon doesn't have a skill because its improvised, so penalty to attack
				prob2defend = prob2defend + 10
			else
				prob2defend = prob2defend + (H.get_skill_level(I.associated_skill) * 10)
		else //the enemy attacked us unarmed or is nonhuman
			if(UH)
				if(UH.used_intent.unarmed)
					prob2defend = prob2defend - (UH.get_skill_level(/datum/skill/combat/unarmed) * 10)
					prob2defend = prob2defend + (H.get_skill_level(/datum/skill/combat/unarmed) * 10)
					if(U.STASPD > L.STASPD) //unarmed is inherently swift
						prob2defend = prob2defend - ((U.STASPD - L.STASPD) * 10)

		if(HAS_TRAIT(L, TRAIT_GUIDANCE))
			prob2defend += 20

		if(HAS_TRAIT(U, TRAIT_GUIDANCE))
			prob2defend -= 20

		if(HAS_TRAIT(L, TRAIT_REVERSE_GUIDANCE))
			prob2defend -= 20
		
		if(HAS_TRAIT(user, TRAIT_CURSE_RAVOX))
			prob2defend -= 40

		// dodging while knocked down sucks ass
		if(!(L.mobility_flags & MOBILITY_STAND))
			prob2defend *= 0.25

		if(H && HAS_TRAIT(H, TRAIT_SENTINELOFWITS))
			var/sentinel = H.calculate_sentinel_bonus()
			prob2defend += sentinel

		if(UH && HAS_TRAIT(UH, TRAIT_ARMOUR_LIKED))
			if(HAS_TRAIT(UH, TRAIT_FENCERDEXTERITY))
				prob2defend -= 10

		// Skill cap raised to 99%
		prob2defend = clamp(prob2defend, 5, 99)

		//------------Dual Wielding Checks------------
		var/attacker_dualw
		var/defender_dualw
		var/extradefroll
		var/mainhand = L.get_active_held_item()
		var/offhand	= L.get_inactive_held_item()

		//Dual Wielder defense disadvantage
		if(mainhand && offhand)
			if(HAS_TRAIT(src, TRAIT_DUALWIELDER) && istype(offhand, mainhand))
				extradefroll = prob(prob2defend)
				defender_dualw = TRUE

		//dual-wielder attack advantage
		var/obj/item/mainh = U.get_active_held_item()
		var/obj/item/offh = U.get_inactive_held_item()
		if(mainh && offh && HAS_TRAIT(U, TRAIT_DUALWIELDER))
			if(istype(mainh, offh))
				attacker_dualw = TRUE
		//----------Dual Wielding check end---------

		var/attacker_feedback 

		if(src.client?.prefs.showrolls)
			var/text = "Roll to dodge... [prob2defend]%"
			if((defender_dualw || attacker_dualw))
				if(defender_dualw && attacker_dualw)
					text += " Our dual wielding cancels out!"
				else
					text += " Twice! Disadvantage! ([(prob2defend / 100) * (prob2defend / 100) * 100]%)"
			to_chat(src, span_info("[text]"))

		// Roll the dodge — store the actual random roll so we can determine margin
		var/roll = rand(1, 100)
		var/dodge_status = FALSE
		var/partial_dodge = FALSE

		if((!defender_dualw && !attacker_dualw) || (defender_dualw && attacker_dualw))
			if(attacker_feedback)
				attacker_feedback = "Advantage cancelled out!"
			if(roll <= prob2defend)
				dodge_status = TRUE
		else if(attacker_dualw)
			if(roll <= prob2defend)
				dodge_status = TRUE
		else if(defender_dualw)
			if((roll <= prob2defend) && extradefroll)
				dodge_status = TRUE

		// Partial dodge: succeeded but roll was in upper 10-20% of success band
		if(dodge_status)
			var/margin_floor = round(prob2defend * 0.8) // top 20% of success = barely dodged
			if(roll > margin_floor && roll <= prob2defend)
				partial_dodge = TRUE

		if(attacker_feedback)
			to_chat(user, span_info("[attacker_feedback]"))

		if(!dodge_status)
			return FALSE
		if(!UH?.mind) // For NPC, reduce the drained to 5 stamina
			drained = drained_npc

		//Tempo bonus
		var/stamdrain = max(drained,5)
		stamdrain -= H.get_tempo_bonus(TEMPO_TAG_STAMLOSS_DODGE)

		if(!H.stamina_add(stamdrain))
			to_chat(src, span_warning("I'm too tired to dodge!"))
			return FALSE

		// Store partial dodge state on the mob temporarily for damage resolution
		H.vars["_partial_dodge"] = partial_dodge

	else //we are a non human
		prob2defend = clamp(prob2defend, 5, 99)
		if(client?.prefs.showrolls)
			to_chat(src, span_info("Roll to dodge... [prob2depend]%"))
		if(!prob(prob2defend))
			return FALSE
	dodgecd = TRUE
	playsound(src, 'sound/combat/dodge.ogg', 100, FALSE)
	if(!HAS_TRAIT(src, TRAIT_DODGE_NO_MOVE))
		throw_at(turfy, 1, 2, src, FALSE)

	// Determine message and return value based on partial/full dodge
	var/is_partial = H ? H.vars["_partial_dodge"] : FALSE
	if(is_partial)
		src.visible_message(span_warning("<b>[src]</b> barely managed to avoid [user]'s [user.used_intent?.masteritem ? "[user.used_intent.masteritem] attack" : "attack"]!"))
	else if(drained > 0)
		src.visible_message(span_warning("<b>[src]</b> dodges [user]'s attack!"))
	else
		src.visible_message(span_warning("<b>[src]</b> easily dodges [user]'s attack!"))

	if(get_dist(src, user) <= user.used_intent?.reach)	//We are still in range of the attacker's weapon post-dodge
		var/probclip = 50
		var/obj/item/IS = L.get_active_held_item()
		var/obj/item/IU = U.get_active_held_item()
		if(IS)
			if(IS.wlength > WLENGTH_NORMAL)
				probclip += (IS.wlength - WLENGTH_NORMAL) * 10
			else
				probclip -= (WLENGTH_NORMAL - IS.wlength) * 10
		var/dist = (user.used_intent?.reach - get_dist(src, user)) - 1
		if(dist > 0)
			probclip += dist * 10
		if(L.STALUC != U.STALUC)
			var/lucmod = L.STALUC - U.STALUC
			probclip += lucmod * 10
		if(prob(probclip) && IS && IU)
			var/intdam = IS.max_blade_int ? INTEG_PARRY_DECAY : INTEG_PARRY_DECAY_NOSHARP
			var/sharp_loss = SHARPNESS_ONHIT_DECAY
			if(istype(user.rmb_intent, /datum/rmb_intent/strong))
				sharp_loss += STRONG_SHP_BONUS
				intdam += STRONG_INTG_BONUS

			IS.take_damage(intdam, BRUTE, IU.d_type)
			IS.remove_bintegrity(sharp_loss, src)

			user.visible_message(span_warning("<b>[user]</b> clips [src]'s weapon!"))
			playsound(user, 'sound/misc/weapon_clip.ogg', 100)
	dodgecd = FALSE
	if(is_partial)
		return DODGE_PARTIAL
	return TRUE

#undef DODGE_PARTIAL
