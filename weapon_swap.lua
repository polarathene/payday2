--WEAPON SWAP v1.0 (Payday 2)
--AUTHOR: Kwhali (Unknown Cheats)
--CREDITS: Maelform (Unknown Cheats)


--CODING NOTES
--Having 2nd thoughts on part of the refactor, extracted common shared vars to reduce code....hurts maintainability a bit with hunting what last set
--a value to the variable, in addition to having to be more careful when adding new code and assigning values if it'd break something....whoops :(
--(I'm lazy) = Sarcasm, seriously though could be problematic, haven't tested thoroughly, can't really invest more time into this
--conditional ternary operator, [condition] and [val_if_true] or [val_if_false]
--truthy/falsey logical operator, [val1] or [val2], left to right evaluation, returns first truthy value
--unpack(), a Lua method that expands a tables values into arguments
--OVK added methods?
--callback(), I'm not actually sure what the first parameters is for, so sticking with repeating the class
--deep_copy(), returns a copy(not reference) of an existing table

Util = Util or class()
--source: http://lua.2524044.n2.nabble.com/table-setn-was-deprecate-what-is-new-function-to-replace-it-td6321872.html
function Util:setn(t,n) --original method 'table.setn()' was made obsolete, can also iterate over table keys with 'table.remove()'
  setmetatable(t,{__len=function() return n end})
end


--base class, run set_weapon while in the briefing screen
WeaponSwap = WeaponSwap or class()
local config = {
  use_dummy = false, --dummy mode will replace the primary/secondary weapon slot with a template and truncate the remaining parts from the blueprint
  dummy_slot = 1, --weapon slot for both primary/secondary categories to use, starts from 1(top left), slot should already have a weapon(I'm lazy)
  --dummy weapons, order is important for unpack(); weapon_id, then blueprint(optional, though try to provide enough mods to replace with target mods)
  dummy_weapon_primaries = {
    'ksg', --weapon_id
    { --blueprint
      'wpn_fps_sho_ksg_body_standard',
      'wpn_fps_sho_ksg_b_long',
      'wpn_fps_upg_ns_sho_salvo_large',
      'wpn_fps_upg_o_mbus_rear',
      'wpn_fps_upg_fl_ass_utg'
    }
  },
  dummy_weapon_secondaries = {
    'olympic', --weapon_id
    { --blueprint
      'wpn_fps_m4_uupg_draghandle',
      'wpn_fps_m4_lower_reciever',
      'wpn_fps_m4_uupg_b_medium',
      'wpn_fps_upg_ns_ass_smg_large',
      'wpn_fps_smg_olympic_fg_railed',
      'wpn_fps_upg_m4_g_ergo',
      'wpn_fps_m4_uupg_m_std',
      'wpn_fps_smg_olympic_s_short',
      'wpn_fps_m4_upper_reciever_edge',
      'wpn_fps_upg_o_eotech',
      'wpn_fps_upg_fl_ass_smg_sho_peqbox',
      'wpn_fps_upg_i_autofire'
    }
  }
}

--manager short names
local m_market = managers.blackmarket
local m_factory = managers.weapon_factory

local ids_unit = Idstring('unit')
local local_peer = managers.network:session():local_peer()

local w_index
local w_category
local w_data

--modify the weapon slot to have a new weapon, avoid using a dummy that would get you cheater tag! (eg DLC weapons you don't own)
function WeaponSwap:replace_slot_with_dummy(category, new_weapon_id, new_blueprint)
  local dummy_data = Global.blackmarket_manager.crafted_items[category][config.dummy_slot]
  if not dummy_data then io.stdout:write('ERROR: WeaponSwap:replace_slot_with_weapon(), Empty Weapon Slot' .. '\n'); return end
  dummy_data.global_values = {} --not sure how important this is (I'm lazy)
  dummy_data.weapon_id  = new_weapon_id
  dummy_data.factory_id = m_factory:get_factory_id_by_weapon_id(new_weapon_id)
  dummy_data.blueprint  = new_blueprint or m_factory:get_default_blueprint_by_factory_id(dummy_data.factory_id)
  m_market:equip_weapon(category, config.dummy_slot) --save/sync the change to you and peers, reloads outfit, may need to unequip/re-equip if slot already equipped (I'm lazy)

  return dummy_data --dummy_data could be w_data but wanted to keep the readability clear in the if conditional
end

--the target weapons category will replace the equivalent equipped category weapon
function WeaponSwap:set_weapon(t_weapon_id, t_blueprint)
  --target weapon to apply
  local t_factory_id = m_factory:get_factory_id_by_weapon_id(t_weapon_id)
  local t_blueprint = t_blueprint or m_factory:get_default_blueprint_by_factory_id(t_factory_id)

  w_index = tweak_data.weapon[t_weapon_id].use_data.selection_index
  w_category = w_index==1 and 'secondaries' or 'primaries'

  --selects weapon to replace
  if config.use_dummy then --optional, this can ensure enough mods for mimicking the target weapons blueprint
    w_data = self:replace_slot_with_dummy(w_category, unpack(config['dummy_weapon_' .. w_category])) --weapon in equipped slot will be modified
  else --default
    w_data = w_category == 'primaries' and m_market:equipped_primary() or m_market:equipped_secondary()
  end

  --important, mimics the weapon class of weapon to switch to
  tweak_data.weapon.factory[w_data.factory_id].unit = tweak_data.weapon.factory[t_factory_id].unit --credit: Maelform
  tweak_data.weapon.factory[w_data.factory_id].animations = tweak_data.weapon.factory[t_factory_id].animations

  --equip the target weapons mods, more importantly, fixes the visual errors
  for i, w_part in ipairs(w_data.blueprint) do
    if i==#w_data.blueprint and #w_data.blueprint < #t_blueprint then
      io.stdout:write('ERROR: WeaponSwap:set_weapon(), Not enough dummy parts to replace' .. '\n')
      break
    end
    self:mimic_part(w_data.blueprint[i], t_blueprint[i])

    if i==#t_blueprint then
      if config.use_dummy and #w_data.blueprint > #t_blueprint then
        Util:setn(w_data.blueprint, #t_blueprint) --discard leftover parts to prevent render issues (destructive to weapon slot blueprint)
      end
      break --all target weapons mods applied, nothing to replace any additional spare parts with
    end
  end

  --load resources for target weapon
  self:load_target_weapon()
end

--replaces the original part with the data of another
function WeaponSwap:mimic_part(original_part, part_to_mimic)
  tweak_data.weapon.factory.parts[original_part] = deep_clone(tweak_data.weapon.factory.parts[part_to_mimic])
end

--NetworkPeer:_reload_outfit(), refactored for weapon loading only, adds target weapon+parts to current outfit_assets
function WeaponSwap:load_target_weapon()
  if local_peer._profile.outfit_string == "" then
    return
  end

  --assign variables based on weapon category, prefix with 'fake_' to avoid name collision with original weapon values
  local category = w_index==1 and 'secondary' or 'primary'
  local cat_w_part = 'fake_' .. (w_index==1 and 'sec' or 'prim') .. '_w_part_'
  self:remove_fake_units(category) --avoid overriding and causing memory/unused resource issues

  local_peer._loading_outfit_assets = true
  local outfit_assets = local_peer._outfit_assets
  local asset_load_result_clbk = self:get_asset_load_result_callback(outfit_assets)
  local complete_outfit = local_peer:blackmarket_outfit() --grabs outfit_string and returns unpacked version

  --add weapon
  local ids_u_name = Idstring(tweak_data.weapon.factory[complete_outfit[category].factory_id].unit)
  outfit_assets.unit['fake_' .. category .. '_w'] = { name = ids_u_name, is_streaming = true }

  --add weapon mods
  local w_parts = managers.weapon_factory:preload_blueprint(complete_outfit[category].factory_id, complete_outfit[category].blueprint, false, function() end, true)
  for part_id, part in pairs(w_parts) do
    outfit_assets.unit[cat_w_part .. tostring(part_id)] = { name = part.name, is_streaming = true }
  end

  --load resources, may be a problem if asset was already loading?
  for asset_id, asset_data in pairs(outfit_assets.unit) do
    if asset_data.is_streaming == true then
      managers.dyn_resource:load(ids_unit, asset_data.name, DynamicResourceManager.DYN_RESOURCES_PACKAGE, asset_load_result_clbk)
    end
  end

  local_peer._all_outfit_load_requests_sent = true
  self:check_if_already_loaded() --if resources are already loaded, callbacks won't fire complete events, this fixes that (eg 2nd game toggle same weapon during briefing)
end

--check for fake units of supplied category in outfit_assets, if any exist unload them
function WeaponSwap:remove_fake_units(category)
  local outfit_assets = local_peer._outfit_assets
  category = category == 'primary' and 'p' or 's'

  --hopefully doesn't cause a problem if the asset is used/loaded in by another peer? (I'm lazy)
  for asset_key, asset_data in pairs(outfit_assets.unit) do
    if string.sub(asset_key, 1, 6)==('fake_' .. category) then
      managers.dyn_resource:unload(ids_unit, asset_data.name, DynamicResourceManager.DYN_RESOURCES_PACKAGE, false)
    end
  end
end

--purely extracted here to simplify overriding this callback when extending the class
function WeaponSwap:get_asset_load_result_callback(outfit_assets)
  return callback(local_peer, local_peer, 'clbk_outfit_asset_loaded', outfit_assets)
end
function WeaponSwap:check_if_already_loaded()
  local_peer:_chk_outfit_loading_complete()
end

--additions to support weapon swapping while in a game
InGame_WeaponSwap = InGame_WeaponSwap or class(WeaponSwap)
--Totally not needed, can keep briefing screen functionality by adding conditional check to InGame_WeaponSwap:_chk_outfit_loading_complete()
--prior to managers.player:player_unit():inventory() which is the source of the problem. Kept here for educational reasons :)
function InGame_WeaponSwap:set_weapon(t_weapon_id, t_blueprint)
  if not game_state_machine or not managers.player:player_unit() then gtrace('ok');return end --prevent crash when running this and not in-game.
  --Super() call, although we overrode the function we can still run the previous code, note the '.' instead of ':' for the function call, and the inclusion of 'self'
  WeaponSwap.set_weapon(self, t_weapon_id, t_blueprint)
end
--override function to use slightly modified callback, postrequiring a conditional callback or a listener/event to
--trigger switch_to_target_weapon works as well
function InGame_WeaponSwap:get_asset_load_result_callback(outfit_assets)
  return callback(self, self, 'clbk_outfit_asset_loaded', outfit_assets)
end
function InGame_WeaponSwap:check_if_already_loaded()
  self:_chk_outfit_loading_complete()
end


--NetworkPeer:clbk_outfit_asset_loaded(), only changed the last function call
function InGame_WeaponSwap:clbk_outfit_asset_loaded(outfit_assets, status, asset_type, asset_name)
  if not local_peer._loading_outfit_assets or local_peer._outfit_assets ~= outfit_assets then
    return
  end

  for asset_id, asset_data in pairs(outfit_assets.unit) do
    if asset_data.name == asset_name then
      asset_data.is_streaming = nil
    end
  end
  if not Global.peer_loading_outfit_assets or not Global.peer_loading_outfit_assets[local_peer._id] then
    self:_chk_outfit_loading_complete() --redirect to modified version
  end
end

--NetworkPeer:_chk_outfit_loading_complete(), added call to switch_to_target_weapon() when complete
function InGame_WeaponSwap:_chk_outfit_loading_complete()
  if not local_peer._loading_outfit_assets or not local_peer._all_outfit_load_requests_sent then
    return
  end
  for asset_type, asset_list in pairs(local_peer._outfit_assets) do
    for asset_id, asset_data in pairs(asset_list) do
      if asset_data.is_streaming then
        return
      end
    end
  end

  local_peer._all_outfit_load_requests_sent = nil
  local_peer._loading_outfit_assets = nil
  --all assets have finished loading in, safe to switch target weapon in now
 managers.player:player_unit():inventory():add_unit_by_factory_name(w_data.factory_id, false, false, w_data.blueprint, w_data.texture_switches)
  managers.network:session():on_peer_outfit_loaded(local_peer)
end
