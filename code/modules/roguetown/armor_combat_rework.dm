/*
 * Combat Rework — Armor Durability & Damage Mitigation
 *
 * Changes:
 *  - All armor item max_integrity multiplied by 5 (done via item initialization override)
 *  - Blunt damage through armor is reduced to 1/5 of normal value
 *  - Penetration that exceeds armor partially converts to extra damage:
 *    extra_damage += pen_damage * 0.5 (in addition to the blunt damage / 5)
 *  - See also: dodge.dm and parry.dm for the dodge/parry/block rework
 */

// ────────────────────────────────────────────────────────────
// Armor durability x5 override
// We use a /obj/item/clothing/initialize override so it applies
// at runtime for all armors that don't manually set obj_integrity.
// ────────────────────────────────────────────────────────────

/obj/item/clothing/armor/Initialize(mapload)
	. = ..()
	if(obj_integrity > 0 && max_integrity > 0)
		max_integrity *= 5
		obj_integrity = max_integrity

// ────────────────────────────────────────────────────────────
// Blunt damage & penetration override
// Hook into run_armor_check to apply the blunt/1-5 rule and
// the penetration bonus damage.
// ────────────────────────────────────────────────────────────

/*
 * run_armor_check is called by the damage pipeline to determine
 * how much armor blocks. After the result is determined we:
 *  1. If the attack is blunt type, return armor_block * 5 as effective
 *     block (i.e. only 1/5 of the damage pierces armor blunt-wise).
 *  2. If penetration > 0, add (pen / 2) as bonus damage on top.
 *
 * Because BYOND's run_armor_check returns a block percentage (0–100),
 * we hook /mob/living/carbon/human/apply_damage instead to intercept
 * the actual damage value and adjust it there.
 */

/mob/living/carbon/human/apply_damage(damage, damagetype, def_zone, blocked, weapon_hit_data, updating_health, forced, sharp, attack_dir)
	if(damagetype == BRUTE && blocked > 0)
		// Retrieve attacker penetration from weapon_hit_data if available
		var/pen = 0
		var/obj/item/W
		if(weapon_hit_data)
			W = weapon_hit_data.weapon
		if(W)
			pen = W.armor_penetration

		// Determine if this is a blunt hit (d_type == "blunt")
		var/is_blunt = FALSE
		if(W)
			is_blunt = (W.d_type == "blunt")
		else
			is_blunt = TRUE // unarmed hits are blunt

		if(is_blunt)
			// Blunt damage through armor = 1/5 of the armor-reduced damage
			// blocked is the percentage absorbed; the remaining (100-blocked)% would hit normally.
			// We take the damage that WOULD have gone through and divide by 5.
			var/armor_factor = (100 - blocked) / 100
			var/damage_through = damage * armor_factor
			var/blunt_damage = damage_through / 5

			// Penetration bonus: pen adds (pen/2)% of the original damage as extra bonus
			var/pen_bonus = 0
			if(pen > 0)
				pen_bonus = round(damage * (pen / 200), 0.1) // pen/2 as % of original damage

			var/total = round(blunt_damage + pen_bonus, 0.1)
			// Call apply_damage with fully blocked = TRUE (0 blocked), adjusted total
			return ..(total, damagetype, def_zone, 0, weapon_hit_data, updating_health, forced, sharp, attack_dir)

	. = ..()
