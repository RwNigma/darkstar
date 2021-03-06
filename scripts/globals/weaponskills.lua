--Contains all common weaponskill calculations including but not limited to:
-- fSTR
-- Alpha
-- Ratio -> cRatio
-- min/max cRatio
-- applications of fTP
-- applications of critical hits ('Critical hit rate varies with TP.')
-- applications of accuracy mods ('Accuracy varies with TP.')
-- applications of damage mods ('Damage varies with TP.')
-- performance of the actual WS (rand numbers, etc)
require("scripts/globals/status");
require("scripts/globals/utils");
require("scripts/globals/magic");

local elementalGorget = { 15495, 15498, 15500, 15497, 15496, 15499, 15501, 15502 };
local elementalBelt =   { 11755, 11758, 11760, 11757, 11756, 11759, 11761, 11762 };

--params contains: ftp100, ftp200, ftp300, str_wsc, dex_wsc, vit_wsc, int_wsc, mnd_wsc, canCrit, crit100, crit200, crit300, acc100, acc200, acc300, ignoresDef, ignore100, ignore200, ignore300, atkmulti
function doPhysicalWeaponskill(attacker, target, params)

    local criticalHit = false;
    local bonusacc = 0;
    local bonusfTP = 0;

    if (attacker:getObjType() == TYPE_PC) then
        local neck = attacker:getEquipID(SLOT_NECK);
        local belt = attacker:getEquipID(SLOT_WAIST);
        local SCProp1, SCProp2, SCProp3 = attacker:getWSSkillchainProp();

        for i,v in ipairs(elementalGorget) do
            if (neck == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    bonusacc = bonusacc + 10;
                    bonusfTP = bonusfTP + 0.1;
                end
                break;
            end
        end

        for i,v in ipairs(elementalBelt) do
            if (belt == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    bonusacc = bonusacc + 10;
                    bonusfTP = bonusfTP + 0.1;
                end
                break;
            end
        end
        --printf("bonusacc = %u bonusfTP = %f", bonusacc, bonusfTP);
    end

	--get fstr
	local fstr = fSTR(attacker:getStat(MOD_STR),target:getStat(MOD_VIT),attacker:getWeaponDmgRank());

	--apply WSC
	local weaponDamage = attacker:getWeaponDmg();
	local weaponType = attacker:getWeaponSkillType(0);

	if (weaponType == SKILL_H2H) then
		local h2hSkill = ((attacker:getSkillLevel(1) * 0.11) + 3);
		weaponDamage = attacker:getWeaponDmg()-3;

		weaponDamage = weaponDamage + h2hSkill;
	end

	local base = weaponDamage + fstr +
		(attacker:getStat(MOD_STR) * params.str_wsc + attacker:getStat(MOD_DEX) * params.dex_wsc +
		 attacker:getStat(MOD_VIT) * params.vit_wsc + attacker:getStat(MOD_AGI) * params.agi_wsc +
		 attacker:getStat(MOD_INT) * params.int_wsc + attacker:getStat(MOD_MND) * params.mnd_wsc +
		 attacker:getStat(MOD_CHR) * params.chr_wsc) * getAlpha(attacker:getMainLvl());

	--Applying fTP multiplier
	local tp = attacker:getTP();
	if attacker:hasStatusEffect(EFFECT_SEKKANOKI) then
		tp = 100;
	end
	local ftp = fTP(tp,params.ftp100,params.ftp200,params.ftp300) + bonusfTP;

	local ignoredDef = 0;
	if (params.ignoresDef == not nil and params.ignoresDef == true) then
		ignoredDef = calculatedIgnoredDef(attacker:getTP(), target:getStat(MOD_DEF), params.ignored100, params.ignored200, params.ignored300);
	end

	--get cratio min and max
	local cratio, ccritratio = cMeleeRatio(attacker, target, params, ignoredDef);
	local ccmin = 0;
	local ccmax = 0;
	local hasMightyStrikes = attacker:hasStatusEffect(EFFECT_MIGHTY_STRIKES);
	local isSneakValid = attacker:hasStatusEffect(EFFECT_SNEAK_ATTACK);
	if (isSneakValid and not (attacker:isBehind(target) or attacker:hasStatusEffect(EFFECT_HIDE))) then
		isSneakValid = false;
	end
	attacker:delStatusEffectsByFlag(EFFECTFLAG_DETECTABLE);
	attacker:delStatusEffect(EFFECT_SNEAK_ATTACK);
	local isTrickValid = attacker:hasStatusEffect(EFFECT_TRICK_ATTACK);
	if (isTrickValid and not attacker:isTrickAttackAvailable(target)) then
		isTrickValid = false;
	end

	local isAssassinValid = isTrickValid;
	if (isAssassinValid and not attacker:hasTrait(68)) then
		isAssassinValid = false;
	end

	local critrate = 0;
    local nativecrit = 0;
    
	if (params.canCrit) then --work out critical hit ratios, by +1ing
		critrate = fTP(attacker:getTP(),params.crit100,params.crit200,params.crit300);
		--add on native crit hit rate (guesstimated, it actually follows an exponential curve)
		local flourisheffect = attacker:getStatusEffect(EFFECT_BUILDING_FLOURISH);
		if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
			critrate = critrate + (10 + flourisheffect:getSubPower()/2)/100;
		end
		nativecrit = (attacker:getStat(MOD_DEX) - target:getStat(MOD_AGI))*0.005; --assumes +0.5% crit rate per 1 dDEX
		nativecrit = nativecrit + (attacker:getMod(MOD_CRITHITRATE)/100);

		if (nativecrit > 0.2) then --caps!
			nativecrit = 0.2;
		elseif (nativecrit < 0.05) then
			nativecrit = 0.05;
		end
		critrate = critrate + nativecrit;
	end


	local dmg = 0;

	--Applying pDIF
	local pdif = generatePdif (cratio[1], cratio[2], true);

	local firsthit = math.random();
	local finaldmg = 0;
	local hitrate = getHitRate(attacker,target,true,bonusacc);
	if (params.acc100~=0) then
		--ACCURACY VARIES WITH TP, APPLIED TO ALL HITS.
		--print("Accuracy varies with TP.");
		hr = accVariesWithTP(getHitRate(attacker,target,false,bonusacc),attacker:getACC(),attacker:getTP(),params.acc100,params.acc200,params.acc300);
		hitrate = hr;
	end

	local tpHitsLanded = 0;
	if ((firsthit <= hitrate or isSneakValid or isAssassinValid or math.random() < attacker:getMod(MOD_ZANSHIN)/100) and
            not target:hasStatusEffect(EFFECT_PERFECT_DODGE) and not target:hasStatusEffect(EFFECT_ALL_MISS) ) then
        dmg = base * ftp;
		if (params.canCrit or isSneakValid or isAssassinValid) then
			local critchance = math.random();
			if (critchance <= critrate or hasMightyStrikes or isSneakValid or isAssassinValid) then --crit hit!
				local cpdif = generatePdif (ccritratio[1], ccritratio[2], true);
				finaldmg = dmg * cpdif;
				if (isSneakValid and attacker:getMainJob()==6) then --have to add on DEX bonus if on THF main
					finaldmg = finaldmg + (attacker:getStat(MOD_DEX) * ftp * cpdif) * ((100+(attacker:getMod(MOD_AUGMENTS_SA)))/100);
				end
				if (isTrickValid and attacker:getMainJob()==6) then
					finaldmg = finaldmg + (attacker:getStat(MOD_AGI) * (1 + attacker:getMod(MOD_TRICK_ATK_AGI)/100) * ftp * cpdif) * ((100+(attacker:getMod(MOD_AUGMENTS_TA)))/100);
				end
			else
				finaldmg = dmg * pdif;
				if (isTrickValid and attacker:getMainJob()==6) then
					finaldmg = finaldmg + (attacker:getStat(MOD_AGI) * (1 + attacker:getMod(MOD_TRICK_ATK_AGI)/100) * ftp * pdif) * ((100+(attacker:getMod(MOD_AUGMENTS_TA)))/100);
				end
			end
		else
			finaldmg = dmg * pdif;
			if (isTrickValid and attacker:getMainJob()==6) then
				finaldmg = finaldmg + (attacker:getStat(MOD_AGI) * (1 + attacker:getMod(MOD_TRICK_ATK_AGI)/100) * ftp * pdif) * ((100+(attacker:getMod(MOD_AUGMENTS_TA)))/100);
			end
		end
		tpHitsLanded = 1;
	end

	if ((attacker:getOffhandDmg() ~= 0) and (attacker:getOffhandDmg() > 0 or weaponType==SKILL_H2H)) then

		local chance = math.random();
		if ((chance<=hitrate or math.random() < attacker:getMod(MOD_ZANSHIN)/100 or isSneakValid)
                and not target:hasStatusEffect(EFFECT_PERFECT_DODGE) and not target:hasStatusEffect(EFFECT_ALL_MISS) ) then --it hit
			pdif = generatePdif (cratio[1], cratio[2], true);
			if (params.canCrit) then
				critchance = math.random();
				if (critchance <= nativecrit or hasMightyStrikes) then --crit hit!
					criticalHit = true;
					cpdif = generatePdif (ccritratio[1], ccritratio[2], true);
					finaldmg = finaldmg + base * cpdif;
				else
					finaldmg = finaldmg + base * pdif;
				end
			else
				finaldmg = finaldmg + base * pdif; --NOTE: not using 'dmg' since fTP is 1.0 for subsequent hits!!
			end
			tpHitsLanded = tpHitsLanded + 1;
		end
	end

	local numHits = getMultiAttacks(attacker, params.numHits);

	local extraHitsLanded = 0;

	if (numHits>1) then

		local hitsdone = 1;
		while (hitsdone < numHits) do
			local chance = math.random();
			if ((chance<=hitrate or math.random() < attacker:getMod(MOD_ZANSHIN)/100) and
                    not target:hasStatusEffect(EFFECT_PERFECT_DODGE) and not target:hasStatusEffect(EFFECT_ALL_MISS) ) then  --it hit
				pdif = generatePdif (cratio[1], cratio[2], true);
				if (params.canCrit) then
					critchance = math.random();
					if (critchance <= nativecrit or hasMightyStrikes) then --crit hit!
						criticalHit = true;
						cpdif = generatePdif (ccritratio[1], ccritratio[2], true);
						finaldmg = finaldmg + base * cpdif;
					else
						finaldmg = finaldmg + base * pdif;
					end
				else
					finaldmg = finaldmg + base * pdif; --NOTE: not using 'dmg' since fTP is 1.0 for subsequent hits!!
				end
				extraHitsLanded = extraHitsLanded + 1;
			end
			hitsdone = hitsdone + 1;
		end
	end
	finaldmg = finaldmg + souleaterBonus(attacker, (tpHitsLanded+extraHitsLanded));
	-- print("Landed " .. hitslanded .. "/" .. numHits .. " hits with hitrate " .. hitrate .. "!");

	finaldmg = target:physicalDmgTaken(finaldmg);
	
    if (weaponType == SKILL_H2H) then
        finaldmg = finaldmg * target:getMod(MOD_HTHRES) / 1000;
    elseif (weaponType == SKILL_DAG or weaponType == SKILL_POL) then
        finaldmg = finaldmg * target:getMod(MOD_PIERCERES) / 1000;
    elseif (weaponType == SKILL_CLB or weaponType == SKILL_STF) then
        finaldmg = finaldmg * target:getMod(MOD_IMPACTRES) / 1000;
    else
        finaldmg = finaldmg * target:getMod(MOD_SLASHRES) / 1000;
    end
    

	attacker:delStatusEffectSilent(EFFECT_BUILDING_FLOURISH);
	return finaldmg, criticalHit, tpHitsLanded, extraHitsLanded;
end;

-- params: ftp100, ftp200, ftp300, wsc_str, wsc_dex, wsc_vit, wsc_agi, wsc_int, wsc_mnd, wsc_chr,
--         ele (ELE_FIRE), skill (SKILL_STF), includemab = true

function doMagicWeaponskill(attacker, target, params)

    local bonusacc = 0;
    local bonusfTP = 0;

    if (attacker:getObjType() == TYPE_PC) then
        local neck = attacker:getEquipID(SLOT_NECK);
        local belt = attacker:getEquipID(SLOT_WAIST);
        local SCProp1, SCProp2, SCProp3 = attacker:getWSSkillchainProp();

        for i,v in ipairs(elementalGorget) do
            if (neck == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    bonusacc = bonusacc + 10;
                    bonusfTP = bonusfTP + 0.1;
                end
                break;
            end
        end

        for i,v in ipairs(elementalBelt) do
            if (belt == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    bonusacc = bonusacc + 10;
                    bonusfTP = bonusfTP + 0.1;
                end
                break;
            end
        end
        --printf("bonusacc = %u bonusfTP = %f", bonusacc, bonusfTP);
    end

    local fint = utils.clamp(8 + (attacker:getStat(MOD_INT) - target:getStat(MOD_INT)), -32, 32);
	local dmg = attacker:getMainLvl() + 2 + (attacker:getStat(MOD_STR) * params.str_wsc + attacker:getStat(MOD_DEX) * params.dex_wsc +
		 attacker:getStat(MOD_VIT) * params.vit_wsc + attacker:getStat(MOD_AGI) * params.agi_wsc +
		 attacker:getStat(MOD_INT) * params.int_wsc + attacker:getStat(MOD_MND) * params.mnd_wsc +
		 attacker:getStat(MOD_CHR) * params.chr_wsc) + fint;
    
    --Applying fTP multiplier
	local tp = attacker:getTP();
	if attacker:hasStatusEffect(EFFECT_SEKKANOKI) then
		tp = 100;
	end
	local ftp = fTP(tp,params.ftp100,params.ftp200,params.ftp300) + bonusfTP;
    
    dmg = dmg * ftp;
    
	dmg = addBonusesAbility(attacker, params.ele, target, dmg, params);
	dmg = dmg * applyResistanceAbility(attacker,target,params.ele,params.skill, 0);
	dmg = target:magicDmgTaken(dmg);
	dmg = adjustForTarget(target,dmg,params.ele);
    
    return dmg, false, 1, 0;
end

function souleaterBonus(attacker, numhits)
	if attacker:hasStatusEffect(EFFECT_SOULEATER) then
		local damage = 0;
		local percent = 0.1;
		if attacker:getMainJob() ~= 8 then
			percent = percent / 2;
		end
		if attacker:getEquipID(SLOT_HEAD) == 12516 or attacker:getEquipID(SLOT_HEAD) == 15232 or attacker:getEquipID(SLOT_BODY) == 14409 or attacker:getEquipID(SLOT_LEGS) == 15370 then
			percent = percent + 0.02;
		end
		local hitscounted = 0;
		while (hitscounted < numhits) do
			local health = attacker:getHP();
			if health > 10 then
				damage = damage + health*percent;
			end
			hitscounted = hitscounted + 1;
		end
		attacker:delHP(numhits*0.10*attacker:getHP());
		return damage;
	else
		return 0;
	end
end;

function accVariesWithTP(hitrate,acc,tp,a1,a2,a3)
	--sadly acc varies with tp ALL apply an acc PENALTY, the acc at various %s are given as a1 a2 a3
	accpct = fTP(tp,a1,a2,a3);
	acclost = acc - (acc*accpct);
	hrate = hitrate - (0.005*acclost);
	--cap it
	if (hrate>0.95) then
		hrate = 0.95;
	end
	if (hrate<0.2) then
		hrate = 0.2;
	end
	return hrate;
end;

function getHitRate(attacker,target,capHitRate,bonus)
	local flourisheffect = attacker:getStatusEffect(EFFECT_BUILDING_FLOURISH);
	if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
		attacker:addMod(MOD_ACC, 20 + flourisheffect:getSubPower())
	end
	local acc = attacker:getACC();
	local eva = target:getEVA();
	if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
		attacker:delMod(MOD_ACC, 20 + flourisheffect:getSubPower())
	end
	if (bonus) then
		acc = acc + bonus;
	end
	
	if (attacker:getMainLvl() > target:getMainLvl()) then --acc bonus!
		acc = acc + ((attacker:getMainLvl()-target:getMainLvl())*4);
	elseif (attacker:getMainLvl() < target:getMainLvl()) then --acc penalty :(
		acc = acc - ((target:getMainLvl()-attacker:getMainLvl())*4);
	end

	local hitdiff = 0;
	local hitrate = 75;
	if (acc>eva) then
	hitdiff = (acc-eva)/2;
	end
	if (eva>acc) then
	hitdiff = ((-1)*(eva-acc))/2;
	end

	hitrate = hitrate+hitdiff;
	hitrate = hitrate/100;


	--Applying hitrate caps
	if (capHitRate) then --this isn't capped for when acc varies with tp, as more penalties are due
		if (hitrate>0.95) then
			hitrate = 0.95;
		end
		if (hitrate<0.2) then
			hitrate = 0.2;
		end
	end
	return hitrate;
end;

function getRangedHitRate(attacker,target,capHitRate,bonus)
	local acc = attacker:getRACC();
	local eva = target:getEVA();

	if (bonus) then
		acc = acc + bonus;
	end

	if (attacker:getMainLvl() > target:getMainLvl()) then --acc bonus!
		acc = acc + ((attacker:getMainLvl()-target:getMainLvl())*4);
	elseif (attacker:getMainLvl() < target:getMainLvl()) then --acc penalty :(
		acc = acc - ((target:getMainLvl()-attacker:getMainLvl())*4);
	end

	local hitdiff = 0;
	local hitrate = 75;
	if (acc>eva) then
	hitdiff = (acc-eva)/2;
	end
	if (eva>acc) then
	hitdiff = ((-1)*(eva-acc))/2;
	end

	hitrate = hitrate+hitdiff;
	hitrate = hitrate/100;


	--Applying hitrate caps
	if (capHitRate) then --this isn't capped for when acc varies with tp, as more penalties are due
		if (hitrate>0.95) then
			hitrate = 0.95;
		end
		if (hitrate<0.2) then
			hitrate = 0.2;
		end
	end
	return hitrate;
end;

function fTP(tp,ftp1,ftp2,ftp3)
	if (tp>=100 and tp<200) then
		return ftp1 + ( ((ftp2-ftp1)/100) * (tp-100));
	elseif (tp>=200 and tp<=300) then
		--generate a straight line between ftp2 and ftp3 and find point @ tp
		return ftp2 + ( ((ftp3-ftp2)/100) * (tp-200));
	else
		print("fTP error: TP value is not between 100-300!");
	end
	return 1; --no ftp mod
end;

function calculatedIgnoredDef(tp, def, ignore1, ignore2, ignore3)
	if (tp>=100 and tp <200) then
		return (ignore1 + ( ((ignore2-ignore1)/100) * (tp-100)))*def;
	elseif (tp>=200 and tp<=300) then
		return (ignore2 + ( ((ignore3-ignore2)/100) * (tp-200)))*def;
	end
	return 1; --no def ignore mod
end
--Given the raw ratio value (atk/def) and levels, returns the cRatio (min then max)
function cMeleeRatio(attacker, defender, params, ignoredDef)

	local flourisheffect = attacker:getStatusEffect(EFFECT_BUILDING_FLOURISH);
	if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
		attacker:addMod(MOD_ATTP, 25 + flourisheffect:getSubPower()/2)
	end
	local cratio = (attacker:getStat(MOD_ATT) * params.atkmulti) / (defender:getStat(MOD_DEF) - ignoredDef);
    cratio = utils.clamp(cratio, 0, 2.25);
	if flourisheffect ~= nil and flourisheffect:getPower() > 1 then
		attacker:delMod(MOD_ATTP, 25 + flourisheffect:getSubPower()/2)
	end
	local levelcor = 0;
	if (attacker:getMainLvl() < defender:getMainLvl()) then
		levelcor = 0.05 * (defender:getMainLvl() - attacker:getMainLvl());
	end

	cratio = cratio - levelcor;

	if (cratio < 0) then
		cratio = 0;
	end
	local pdifmin = 0;
	local pdifmax = 0;

    --max

    if (cratio < 0.5) then
        pdifmax = cratio + 0.5;
    elseif (cratio < 0.7) then
        pdifmax = 1;
    elseif (cratio < 1.2) then
        pdifmax = cratio + 0.3;
    elseif (cratio < 1.5) then
        pdifmax = (cratio * 0.25) + cratio;
    elseif (cratio < 1.5) then
        pdifmax = cratio + 0.375;
    else
        pdifmax = 3;
    end
    --min

    if (cratio < 0.38) then
        pdifmin = 0;
    elseif (cratio < 1.25) then
        pdifmin = cratio * (1176/1024) - (448/1024);
    elseif (cratio < 1.51) then
        pdifmin = 1;
    elseif (cratio < 2.44) then
        pdifmin = cratio * (1176/1024) - (775/1024);
    else
        pdifmin = cratio - 0.375;
    end

	local pdif = {};
	pdif[1] = pdifmin;
	pdif[2] = pdifmax;

	local pdifcrit = {};
    cratio = cratio + 1;
    cratio = utils.clamp(cratio, 0, 3);

	--printf("ratio: %f min: %f max %f\n", cratio, pdifmin, pdifmax);

    if (cratio < 0.5) then
        pdifmax = cratio + 0.5;
    elseif (cratio < 0.7) then
        pdifmax = 1;
    elseif (cratio < 1.2) then
        pdifmax = cratio + 0.3;
    elseif (cratio < 1.5) then
        pdifmax = (cratio * 0.25) + cratio;
    elseif (cratio < 1.5) then
        pdifmax = cratio + 0.375;
    else
        pdifmax = 3;
    end
    --min

    if (cratio < 0.38) then
        pdifmin = 0;
    elseif (cratio < 1.25) then
        pdifmin = cratio * (1176/1024) - (448/1024);
    elseif (cratio < 1.51) then
        pdifmin = 1;
    elseif (cratio < 2.44) then
        pdifmin = cratio * (1176/1024) - (775/1024);
    else
        pdifmin = cratio - 0.375;
    end

    local critbonus = attacker:getMod(MOD_CRIT_DMG_INCREASE)
    critbonus = utils.clamp(critbonus, 0, 100);
    pdifcrit[1] = pdifmin * ((100 + critbonus)/100);
    pdifcrit[2] = pdifmax * ((100 + critbonus)/100);
    
	return pdif, pdifcrit;
end;

function cRangedRatio(attacker, defender, params, ignoredDef)

	local cratio = attacker:getRATT() / (defender:getStat(MOD_DEF) - ignoredDef);

	local levelcor = 0;
	if (attacker:getMainLvl() < defender:getMainLvl()) then
		levelcor = 0.025 * (defender:getMainLvl() - attacker:getMainLvl());
	end

	cratio = cratio - levelcor;

	cratio = cratio * params.atkmulti;

	if (cratio > 3 - levelcor) then
		cratio = 3 - levelcor;
	end

	if (cratio < 0) then
		cratio = 0;
	end

	--max
	local pdifmax = 0;
	if (cratio < 0.9) then
		pdifmax = cratio * (10/9);
	elseif (cratio < 1.1) then
		pdifmax = 1;
	else
		pdifmax = cratio;
	end

	--min
	local pdifmin = 0;
	if (cratio < 0.9) then
		pdifmin = cratio;
	elseif (cratio < 1.1) then
		pdifmin = 1;
	else
		pdifmin = (cratio * (20/19))-(3/19);
	end

	pdif = {};
	pdif[1] = pdifmin;
	pdif[2] = pdifmax;
	--printf("ratio: %f min: %f max %f\n", cratio, pdifmin, pdifmax);
	pdifcrit = {};

	pdifmin = pdifmin * 1.25;
	pdifmax = pdifmax * 1.25;

	pdifcrit[1] = pdifmin;
	pdifcrit[2] = pdifmax;

	return pdif, pdifcrit;

end

--Given the attacker's str and the mob's vit, fSTR is calculated
function fSTR(atk_str,def_vit,base_dmg)
	local dSTR = atk_str - def_vit;
	if (dSTR >= 12) then
		fSTR2 = ((dSTR+4)/2);
	elseif (dSTR >= 6) then
		fSTR2 = ((dSTR+6)/2);
	elseif (dSTR >= 1) then
		fSTR2 = ((dSTR+7)/2);
	elseif (dSTR >= -2) then
		fSTR2 = ((dSTR+8)/2);
	elseif (dSTR >= -7) then
		fSTR2 = ((dSTR+9)/2);
	elseif (dSTR >= -15) then
		fSTR2 = ((dSTR+10)/2);
	elseif (dSTR >= -21) then
		fSTR2 = ((dSTR+12)/2);
	else
		fSTR2 = ((dSTR+13)/2);
	end
	--Apply fSTR caps.
	if (fSTR2<((base_dmg/9)*(-1))) then
		fSTR2 = (base_dmg/9)*(-1);
	elseif (fSTR2>((base_dmg/9)+8)) then
		fSTR2 = (base_dmg/9)+8;
	end
	return fSTR2;
end;

--obtains alpha, used for working out WSC
function getAlpha(level)
    alpha = 1.00;
    if (level <= 5) then
        alpha = 1.00;
    elseif (level <= 11) then
        alpha = 0.99;
    elseif (level <= 17) then
        alpha = 0.98;
    elseif (level <= 23) then
        alpha = 0.97;
    elseif (level <= 29) then
        alpha = 0.96;
    elseif (level <= 35) then
        alpha = 0.95;
    elseif (level <= 41) then
        alpha = 0.94;
    elseif (level <= 47) then
        alpha = 0.93;
    elseif (level <= 53) then
        alpha = 0.92;
    elseif (level <= 59) then
        alpha = 0.91;
    elseif (level <= 61) then
        alpha = 0.90;
    elseif (level <= 63) then
        alpha = 0.89;
    elseif (level <= 65) then
        alpha = 0.88;
    elseif (level <= 67) then
        alpha = 0.87;
    elseif (level <= 69) then
        alpha = 0.86;
    elseif (level <= 71) then
        alpha = 0.85;
    elseif (level <= 73) then
        alpha = 0.84;
    elseif (level <= 75) then
        alpha = 0.83;
    elseif (level < 99) then
        alpha = 0.85;
    else
        alpha = 1; -- Retail has no alpha anymore!
    end
    return alpha;
end;

 --params contains: ftp100, ftp200, ftp300, str_wsc, dex_wsc, vit_wsc, int_wsc, mnd_wsc, canCrit, crit100, crit200, crit300, acc100, acc200, acc300, ignoresDef, ignore100, ignore200, ignore300, atkmulti
 function doRangedWeaponskill(attacker, target, params)

    local bonusacc = 0;
    local bonusfTP = 0;

    if (attacker:getObjType() == TYPE_PC) then
        local neck = attacker:getEquipID(SLOT_NECK);
        local belt = attacker:getEquipID(SLOT_WAIST);
        local SCProp1, SCProp2, SCProp3 = attacker:getWSSkillchainProp();

        for i,v in ipairs(elementalGorget) do
            if (neck == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    bonusacc = bonusacc + 10;
                    bonusfTP = bonusfTP + 0.1;
                end
                break;
            end
        end

        for i,v in ipairs(elementalBelt) do
            if (belt == v) then
                if (doesElementMatchWeaponskill(i, SCProp1) or doesElementMatchWeaponskill(i, SCProp2) or doesElementMatchWeaponskill(i, SCProp3)) then
                    bonusacc = bonusacc + 10;
                    bonusfTP = bonusfTP + 0.1;
                end
                break;
            end
        end
        --printf("bonusacc = %u bonusfTP = %f", bonusacc, bonusfTP);
    end

	--get fstr
	local fstr = fSTR(attacker:getStat(MOD_STR),target:getStat(MOD_VIT),attacker:getRangedDmgForRank());

	--apply WSC
	local base = attacker:getRangedDmg() + fstr +
		(attacker:getStat(MOD_STR) * params.str_wsc + attacker:getStat(MOD_DEX) * params.dex_wsc +
		 attacker:getStat(MOD_VIT) * params.vit_wsc + attacker:getStat(MOD_AGI) * params.agi_wsc +
		 attacker:getStat(MOD_INT) * params.int_wsc + attacker:getStat(MOD_MND) * params.mnd_wsc +
		 attacker:getStat(MOD_CHR) * params.chr_wsc) * getAlpha(attacker:getMainLvl());

	--Applying fTP multiplier
	local ftp = fTP(attacker:getTP(),params.ftp100,params.ftp200,params.ftp300) + bonusfTP;

	local ignoredDef = 0;
	if (params.ignoresDef == not nil and params.ignoresDef == true) then
		ignoredDef = calculatedIgnoredDef(attacker:getTP(), target:getStat(MOD_DEF), params.ignored100, params.ignored200, params.ignored300);
	end

	--get cratio min and max
	local cratio, ccritratio = cRangedRatio( attacker, target, params, ignoredDef);
	local ccmin = 0;
	local ccmax = 0;
	local hasMightyStrikes = attacker:hasStatusEffect(EFFECT_MIGHTY_STRIKES);
	local critrate = 0;
	if (params.canCrit) then --work out critical hit ratios, by +1ing
		critrate = fTP(attacker:getTP(),params.crit100,params.crit200,params.crit300);
		--add on native crit hit rate (guesstimated, it actually follows an exponential curve)
		local nativecrit = (attacker:getStat(MOD_DEX) - target:getStat(MOD_AGI))*0.005; --assumes +0.5% crit rate per 1 dDEX
		if (nativecrit > 0.2) then --caps!
			nativecrit = 0.2;
		elseif (nativecrit < 0.05) then
			nativecrit = 0.05;
		end
		critrate = critrate + nativecrit;
	end


	local dmg = base * ftp;

	--Applying pDIF
	local pdif = generatePdif (cratio[1],cratio[2], false);

	--First hit has 95% acc always. Second hit + affected by hit rate.
	local firsthit = math.random();
	local finaldmg = 0;
	local hitrate = getRangedHitRate(attacker,target,true,bonusacc);
	if (params.acc100~=0) then
		--ACCURACY VARIES WITH TP, APPLIED TO ALL HITS.
		--print("Accuracy varies with TP.");
		hr = accVariesWithTP(getRangedHitRate(attacker,target,false,bonusacc),attacker:getRACC(),attacker:getTP(),params.acc100,params.acc200,params.acc300);
		hitrate = hr;
	end

	local tpHitsLanded = 0;
	if (firsthit <= hitrate) then
		if (params.canCrit) then
			local critchance = math.random();
			if (critchance <= critrate or hasMightyStrikes) then --crit hit!
				local cpdif = generatePdif (ccritratio[1], ccritratio[2], false);
				finaldmg = dmg * cpdif;
			else
				finaldmg = dmg * pdif;
			end
		else
			finaldmg = dmg * pdif;
		end
		tpHitsLanded = 1;
	end

	local numHits = params.numHits;

	local extraHitsLanded = 0;
	if (numHits>1) then
		if (params.acc100==0) then
			--work out acc since we actually need it now
			hitrate = getRangedHitRate(attacker,target,true,bonusacc);
		end

		hitsdone = 1;
		while (hitsdone < numHits) do
			chance = math.random();
			if (chance<=hitrate) then --it hit
				pdif = generatePdif (cratio[1],cratio[2], false);
				if (canCrit) then
					critchance = math.random();
					if (critchance <= critrate or hasMightyStrikes) then --crit hit!
						cpdif = generatePdif (ccritratio[1], ccritratio[2], false);
						finaldmg = finaldmg + base * cpdif;
					else
						finaldmg = finaldmg + base * pdif;
					end
				else
					finaldmg = finaldmg + base * pdif; --NOTE: not using 'dmg' since fTP is 1.0 for subsequent hits!!
				end
				extraHitsLanded = extraHitsLanded + 1;
			end
			hitsdone = hitsdone + 1;
		end
	end
	--print("Landed " .. hitslanded .. "/" .. numHits .. " hits with hitrate " .. hitrate .. "!");

	finaldmg = target:rangedDmgTaken(finaldmg);
    finaldmg = finaldmg * target:getMod(MOD_PIERCERES) / 1000;

	return finaldmg, tpHitsLanded, extraHitsLanded;
end;

function getMultiAttacks(attacker, numHits)
	local bonusHits = 0;
	local tripleChances = 1;
	local doubleRate = attacker:getMod(MOD_DOUBLE_ATTACK)/100;
	local tripleRate = attacker:getMod(MOD_TRIPLE_ATTACK)/100;

	--triple only procs on first hit, or first two hits if dual wielding
	if (attacker:getOffhandDmg() > 0) then
		tripleChances = 2;
	end

	for i = 1, numHits, 1 do
		chance = math.random();
		if (chance < tripleRate and i <= tripleChances) then
			bonusHits = bonusHits + 2;
		else
			--have to check if triples are possible, or else double attack chance
			-- gets accidentally increased by triple chance (since it can only proc on 1 or 2)
			if (i <= tripleChances) then
				if (chance < tripleRate + doubleRate) then
					bonusHits = bonusHits + 1;
				end
			else
				if (chance < doubleRate) then
					bonusHits = bonusHits + 1;
				end
			end
		end
		if (i == 1) then
			attacker:delStatusEffect(EFFECT_ASSASSIN_S_CHARGE);
			attacker:delStatusEffect(EFFECT_WARRIOR_S_CHARGE);

			-- recalculate mods
			doubleRate = attacker:getMod(MOD_DOUBLE_ATTACK)/100;
			tripleRate = attacker:getMod(MOD_TRIPLE_ATTACK)/100;
		end
	end
	if ((numHits + bonusHits ) > 8) then
		return 8;
	end
	return numHits + bonusHits;
end;

function generatePdif (cratiomin, cratiomax, melee)
	local pdif = math.random(cratiomin*1000, cratiomax*1000) / 1000;
	if (melee) then
		pdif = pdif * (math.random(100,105)/100);
	end
	return pdif;
end

function getStepAnimation(skill)
	if skill <= 1 then
		return 15;
	elseif skill <= 3 then
		return 14;
	elseif skill == 4 then
		return 19;
	elseif skill == 5 then
		return 16;
	elseif skill <= 7 then
		return 18;
	elseif skill == 8 then
		return 20;
	elseif skill == 9 then
		return 21;
	elseif skill == 10 then
		return 22;
	elseif skill == 11 then
		return 17;
	elseif skill == 12 then
		return 23;
	else
		return 0;
	end	
end

function getFlourishAnimation(skill)
	if skill <= 1 then
		return 25;
	elseif skill <= 3 then
		return 24;
	elseif skill == 4 then
		return 29;
	elseif skill == 5 then
		return 26;
	elseif skill <= 7 then
		return 28;
	elseif skill == 8 then
		return 30;
	elseif skill == 9 then
		return 31;
	elseif skill == 10 then
		return 32;
	elseif skill == 11 then
		return 27;
	elseif skill == 12 then
		return 33;
	else
		return 0;
	end	
end
