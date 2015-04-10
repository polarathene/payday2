--WEAPON SWAP v1.1 (Payday 2)
--AUTHOR: Kwhali (Unknown Cheats)
--CREDITS: Maelform (Unknown Cheats)


--USAGE
--Run this code at the bottom of the script via keybind or make this script persistent and call the usage via keybind elsewhere
--local wpn = 'flamethrower_mk2'
--local bp = {'wpn_fps_fla_mk2_empty', 'wpn_fps_fla_mk2_body', 'wpn_fps_fla_mk2_mag'}
--Use one of these two methods below:
--WeaponSwap:set_weapon(wpn, bp) --Trigger only during briefing screen
--InGame_WeaponSwap:set_weapon(wpn, bp) --Trigger only while in-game(playing level). (Recommended)
--Call again with a different wpn(eg 'm134'(minigun) or 'rpg7'(rocket launcher)) and bp(optional) to load in another weapon
--The weapon will swap with the category it belongs to(primary/secondary)
--You can also pass in a config option as a third argument when running as a persistscript to change the default one while in-game.


--Troubleshooting
--If you have any problem try enable dummy mode to fix, note this will change the real weapon in your dummy slot(default=1, top left of category) (InGame version does not alter your real weapon or change the slot)
--If that doesn't work, try use a different weapon of that category or change the dummy weapon in config(along with enough blueprint parts for the dummy)
--Another way around problem weapons is to do the swap while having the opposite category equipped, eg, for 'rpg7' have your primary equipped, then after the swap, switch to your secondary('rpg7')


--CODING NOTES
--Huge amount of comments, hope this serves as a good reference to those new to lua and modding Payday 2 :)
--Having 2nd thoughts on part of the refactor, extracted common shared vars to reduce code....hurts maintainability a bit with hunting what last set
--a value to the variable, in addition to having to be more careful when adding new code and assigning values if it'd break something....whoops :(
--(I'm lazy) = Sarcasm, seriously though could be problematic, haven't tested thoroughly, can't really invest more time into this
--conditional ternary operator, [condition] and [val_if_true] or [val_if_false]
--truthy/falsey logical operator, [val1] or [val2], left to right evaluation, returns first truthy value
--unpack(), a Lua method that expands a tables values into arguments
--OVK added methods?:
--callback(), I'm not actually sure what the first parameters is for, so sticking with repeating the class
--deep_copy(), returns a copy(not reference) of an existing table


Util = Util or class()
--given a table truncate the tail at n
function Util:truncate(t,n) --original method 'table.setn()' was made obsolete
  for k,v in ipairs(t) do
    if k>n then t[k]=nil end
  end
end


function Util:extract_duplicates(t1, t2)
  if #t1>#t2 then --iterate over table with fewest parts
    local tmp = t2
    t2 = t1
    t1 = tmp
  end

  local t3 = {} --stores the duplicate parts
  for i, v in ipairs(t1) do
    for j, v2 in ipairs(t2) do
      --if v==v2 then t3[#t3+1] = v; t1[i]=nil; t2[j]=nil end --would be nicer but would have to cater for nil as this doesn't remove for value only tables
      if v==v2 then
        t3[#t3+1] = v;
        table.remove(t1, i)
        table.remove(t2, j)
        i=i-1
        end
    end
  end

  return #t3>0 and t3 or nil
end


function Util:concat_tables(t1, t2) --adds t2 values to t1, should only be used for value only tables
  for i, v in ipairs(t2) do
    table.insert(t1, v)
  end
end


--errors will be sent to this function, you can handle logging/output here
function Util:log(content)
  if not content then return end
  io.stdout:write(content .. '\n')
end


--base class, run set_weapon while in the briefing screen
WeaponSwap = WeaponSwap or class()
function WeaponSwap:init(config)
  self.config = config or { --if no config object provided from user, we'll use this instead
    use_dummy = true, --dummy mode will replace the primary/secondary weapon slot with a template and truncate the remaining parts from the blueprint
    dummy_slot = 1, --weapon slot for both primary/secondary categories to use, starts from 1(top left)

    --dummy weapons, order is important for unpack(); weapon_id, then blueprint(optional, though try to provide enough mods to replace with target mods)
    dummy_weapon_primaries = { --could do with a weapon with more mods (I'm lazy)
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
        'wpn_fps_upg_i_autofire' --gage dlc
      }
    }
  }

  --manager short names
  self.m_market      = managers.blackmarket
  self.m_factory     = managers.weapon_factory

  self.ids_unit      = Idstring('unit')
  self.local_peer    = managers.network:session():local_peer()
  self.parts_to_keep = nil
  self.w_index       = nil
  self.w_category    = nil
  self.w_data        = nil
end


--modify the weapon slot to have a new weapon, avoid using a dummy that would get you cheater tag! (eg DLC weapons you don't own)
function WeaponSwap:replace_slot_with_dummy(category, new_weapon_id, new_blueprint)
  local dummy_data = self==WeaponSwap and Global.blackmarket_manager.crafted_items[category][self.config.dummy_slot] or {} --base class will overwrite weapon slot data, the extended InGame class doesn't need to and will just reference data :)
  if not dummy_data then Util:log('ERROR: WeaponSwap:replace_slot_with_weapon(), Empty Weapon Slot'); return end

  dummy_data.global_values = {} --not sure how important this is (I'm lazy)
  dummy_data.texture_switches = {} --not sure how important this is (I'm lazy)
  dummy_data.weapon_id  = new_weapon_id
  dummy_data.factory_id = self.m_factory:get_factory_id_by_weapon_id(new_weapon_id)
  dummy_data.blueprint  = new_blueprint or self.m_factory:get_default_blueprint_by_factory_id(dummy_data.factory_id)

  --if this is the base class then we want to equip the dummy weapon slot
  if self==WeaponSwap then
    if(self.m_market:equipped_weapon_slot(category) == self.config.dummy_slot) then
      self.local_peer:_reload_outfit() --equip_weapon()->set_outfit_string() doesn't call _reload_outfit() if the outfit_string hasn't changed(eg weapon slot you equip is already equipped).
    end
    self.m_market:equip_weapon(category, self.config.dummy_slot) --save/sync the change to you and peers, reloads outfit
  end

  return dummy_data --dummy_data could be w_data(and thus no need to return) but wanted to keep the readability clear in the if conditional(that calls this function)
end


--the target weapons category will replace the equivalent equipped category weapon
function WeaponSwap:set_weapon(t_weapon_id, t_blueprint, _config)
  --_config can be table(assumed correct key/values), or boolean flag to toggle use of dummy weapon/mode
  if type(_config)=='table' then
    self:init(_config)
  else
    self:init() --no config object provided, init with defaults
    if type(_config)=='boolean' then self.config.use_dummy = _config end --if a boolean flag was given we'll update this property
  end

  --target weapon to apply
  local t_factory_id = self.m_factory:get_factory_id_by_weapon_id(t_weapon_id)
  local t_blueprint = t_blueprint or self.m_factory:get_default_blueprint_by_factory_id(t_factory_id)
  if not t_factory_id or not t_blueprint then
    Util:log('ERROR: WeaponSwap:set_weapon(), invalid weapon_id and/or blueprint')
    return
  end

  self.w_index = tweak_data.weapon[t_weapon_id].use_data.selection_index
  self.w_category = self.w_index==1 and 'secondaries' or 'primaries'

  --selects weapon to replace
  if self.config.use_dummy then --optional, this can ensure enough mods for mimicking the target weapons blueprint
    self.w_data = self:replace_slot_with_dummy(self.w_category, unpack(self.config['dummy_weapon_' .. self.w_category])) --weapon in equipped slot will be modified
  else --default
    self.w_data = self.w_category == 'primaries' and self.m_market:equipped_primary() or self.m_market:equipped_secondary()
  end

  --important, mimics the weapon class of weapon to switch to
  tweak_data.weapon.factory[self.w_data.factory_id].unit = tweak_data.weapon.factory[t_factory_id].unit --credit: Maelform
  tweak_data.weapon.factory[self.w_data.factory_id].animations = tweak_data.weapon.factory[t_factory_id].animations

  --equip the target weapons mods, more importantly, fixes the visual errors
  self.parts_to_keep = Util:extract_duplicates(self.w_data.blueprint, t_blueprint) --we don't want to tamper with parts we want to use!
  for i, w_part in ipairs(self.w_data.blueprint) do
    if i==#self.w_data.blueprint and #self.w_data.blueprint < #t_blueprint then
      Util:log('ERROR: WeaponSwap:set_weapon(), Not enough dummy parts to replace')
      break
    end

    self:mimic_part(self.w_data.blueprint[i], t_blueprint[i])

    if i==#t_blueprint then
      if self.config.use_dummy and #self.w_data.blueprint > #t_blueprint then
        Util:truncate(self.w_data.blueprint, #t_blueprint) --discard leftover parts to prevent render issues (destructive to weapon slot blueprint)
      end
      break --all target weapons mods applied, nothing to replace any additional spare parts with
    end
  end

  --load resources for target weapon
  self:load_target_weapon()
end


--replaces the original part with the data of another
function WeaponSwap:mimic_part(original_part, part_to_mimic)
  if not tweak_data.weapon.factory.parts[part_to_mimic] then Util:log('ERROR: WeaponSwap:mimic_part(), invalid weapon part name: ' .. tostring(part_to_mimic)) return end
  tweak_data.weapon.factory.parts[original_part] = deep_clone(tweak_data.weapon.factory.parts[part_to_mimic])
end


--NetworkPeer:_reload_outfit(), refactored for weapon loading only, adds target weapon+parts to current outfit_assets
function WeaponSwap:load_target_weapon()
  if self.local_peer._profile.outfit_string == "" then
    return
  end

  --assign variables based on weapon category, prefix with 'fake_' to avoid name collision with original weapon values
  local category = self.w_index==1 and 'secondary' or 'primary'
  local cat_w_part = 'fake_' .. (self.w_index==1 and 'sec' or 'prim') .. '_w_part_'
  self:remove_fake_units(category) --avoid overriding and causing memory/unused resource issues

  self.local_peer._loading_outfit_assets = true
  local outfit_assets = self.local_peer._outfit_assets
  local asset_load_result_clbk = self:get_asset_load_result_callback(outfit_assets)

  --add weapon
  local ids_u_name = Idstring(tweak_data.weapon.factory[self.w_data.factory_id].unit)
  outfit_assets.unit['fake_' .. category .. '_w'] = { name = ids_u_name }

  --add weapon mods
  local w_parts = self.m_factory:preload_blueprint(self.w_data.factory_id, self.w_data.blueprint, false, function() end, true)
  for part_id, part in pairs(w_parts) do
    outfit_assets.unit[cat_w_part .. tostring(part_id)] = { name = part.name }
  end

  --load resources, may be a problem if asset was already loading?
  category = category == 'primary' and 'p' or 's' --reassigning this variables value due to context, it's local and the old value is not referenced again
  for asset_key, asset_data in pairs(outfit_assets.unit) do
    if string.sub(asset_key, 1, 6)==('fake_' .. category) then
      asset_data.is_streaming = true
      managers.dyn_resource:load(self.ids_unit, asset_data.name, DynamicResourceManager.DYN_RESOURCES_PACKAGE, asset_load_result_clbk)
    end
  end

  --these parts already exist in outfit_assets, we don't want to prepend the 'fake_' prefix or reload them, so they're added afterwards back to the blueprint
  if self.parts_to_keep then Util:concat_tables(self.w_data.blueprint, self.parts_to_keep) end--adds the extracted duplicate parts back so we can use them

  self.local_peer._all_outfit_load_requests_sent = true
  self:check_if_already_loaded() --if resources are already loaded, callbacks won't fire complete events, this fixes that (eg 2nd game toggle same weapon during briefing)
end


--check for fake units of supplied category in outfit_assets, if any exist unload them
function WeaponSwap:remove_fake_units(category)
  local outfit_assets = self.local_peer._outfit_assets
  category = category == 'primary' and 'p' or 's'

  --hopefully doesn't cause a problem if the asset is used/loaded in by another peer? (I'm lazy)
  for asset_key, asset_data in pairs(outfit_assets.unit) do
    if string.sub(asset_key, 1, 6)==('fake_' .. category) then
      managers.dyn_resource:unload(self.ids_unit, asset_data.name, DynamicResourceManager.DYN_RESOURCES_PACKAGE, false)
    end
  end
end


--purely extracted here to simplify overriding this callback when extending the class
function WeaponSwap:get_asset_load_result_callback(outfit_assets)
  return callback(self.local_peer, self.local_peer, 'clbk_outfit_asset_loaded', outfit_assets)
end
function WeaponSwap:check_if_already_loaded()
  self.local_peer:_chk_outfit_loading_complete()
end


--additions to support weapon swapping while in a game
InGame_WeaponSwap = InGame_WeaponSwap or class(WeaponSwap)
--Totally not needed, can keep briefing screen functionality by adding conditional check to InGame_WeaponSwap:_chk_outfit_loading_complete()
--prior to managers.player:player_unit():inventory() which is the source of the problem. Kept here for educational reasons :)
function InGame_WeaponSwap:set_weapon( ... ) -- '...' means take a variable amount of arguments, we could have alternatively typed the same parameters as the original function
  if not game_state_machine or not managers.player:player_unit() then return end --prevent crash when running this and not in-game.
  --Super() call, although we overrode the function we can still run the previous code, note the '.' instead of ':' for the function call, and the inclusion of 'self'
  WeaponSwap.set_weapon(self, ... ) --send given '...' arguements to super() call
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
--there is a bug for some weapon combinations(targets + dummy) where this callback is never called, whatever the cause the game will crash (BUG)
function InGame_WeaponSwap:clbk_outfit_asset_loaded(outfit_assets, status, asset_type, asset_name)
  if not self.local_peer._loading_outfit_assets or self.local_peer._outfit_assets ~= outfit_assets then
    return
  end

  for asset_key, asset_data in pairs(outfit_assets.unit) do
    if asset_data.name == asset_name then
      asset_data.is_streaming = nil
    end
  end
  if not Global.peer_loading_outfit_assets or not Global.peer_loading_outfit_assets[self.local_peer._id] then
    self:_chk_outfit_loading_complete() --redirect to modified version
  end
end


--NetworkPeer:_chk_outfit_loading_complete(), added call to switch_to_target_weapon() when complete
function InGame_WeaponSwap:_chk_outfit_loading_complete()
  if not self.local_peer._loading_outfit_assets or not self.local_peer._all_outfit_load_requests_sent then
    return
  end
  for asset_type, asset_list in pairs(self.local_peer._outfit_assets) do
    for asset_key, asset_data in pairs(asset_list) do
      if asset_data.is_streaming then
        return --an asset is still loading, we aren't finished, prevent running code below
      end
    end
  end

  self.local_peer._all_outfit_load_requests_sent = nil
  self.local_peer._loading_outfit_assets = nil
  --all assets have finished loading in, safe to switch target weapon in now
  managers.player:player_unit():inventory():add_unit_by_factory_name(self.w_data.factory_id, false, false, self.w_data.blueprint, self.w_data.texture_switches)
  managers.network:session():on_peer_outfit_loaded(self.local_peer)
end
