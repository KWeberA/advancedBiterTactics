local MOD_NAME = script.mod_name or "advanced-biter-tactics"

local PROCESS_INTERVAL = 30
local MAX_GROUPS_PER_PASS = 12
local CONTACT_RADIUS = 24
local WALL_NETWORK_LIMIT = 256
local WALL_NETWORK_RADIUS = 64
local MAX_FLANK_STEPS = 3
local MAX_REPLANS = 2
local MAX_SCRIPT_CONTROL_TICKS = 1800
local SIEGE_SITE_TTL = 3600
local SIEGE_SITE_RADIUS = 96
local WALL_NEIGHBOR_RADIUS = 1.6
local OUTSIDE_SAMPLE_OFFSET = 1.8
local ATTACK_RADIUS = 4
local RALLY_MIN_DISTANCE = 4
local RALLY_BASE_MAX_DISTANCE = 18
local RALLY_HARD_MAX_DISTANCE = 28
local FALLBACK_ATTACK_TICKS = 300
local ATTACK_COMMAND_TIMEOUT = 900
local MOVE_COMMAND_TIMEOUT = 600
local UNIT_PROBE_FALLBACK = "small-biter"
local DESIRED_BREACH_SEGMENTS = 3
local MIN_BREACH_SEGMENTS = 2
local SUPPORT_MAX_DRIFT = 4
local SUPPORT_RETURN_RADIUS = 2
local SUPPORT_STANDOFF_MIN_DISTANCE = 4
local MOVE_REASSERT_TICKS = 60
local BREACH_TARGET_RADIUS = 0.6
local BREACH_TARGET_SEARCH_DISTANCE = 3.1
local LOCAL_ASSAULT_RADIUS = 32
local BREACH_ENTRY_DISTANCE = 4
local INSIDE_RALLY_DISTANCE = 6
local BREACH_EXPLOIT_DISTANCE = 12
local BREACH_CORRIDOR_DISTANCE = 6
local POST_BREACH_ENTRY_RADIUS = 3
local POST_BREACH_ASSAULT_HANDOFF_TICKS = 180
local MAX_MELEE_PER_TURRET = 10
local SUPPORT_FOLLOW_TRIGGER_DISTANCE = 6
local SUPPORT_FOLLOW_DISTANCE = 5
local SUPPORT_FOLLOW_MIN_DISTANCE = 2
local BREACH_PRESSURE_TIMEOUT = 240
local BREACH_PRESSURE_EVENT_COOLDOWN = 30
local STALL_TIMEOUT_TICKS = 360
local COVERAGE_PATH_SAMPLE_SPACING = 1.5
local MEANINGFUL_PROGRESS_DISTANCE_SQ = 2.25
local FLAME_LANE_COUNT = 3
local FLAME_LANE_SPREAD = 4
local FLAME_HAZARD_RADIUS = 2.5
local RANGED_CONE_GROUP_LIMIT = 3
local RANGED_CONE_LANE_COUNT = 5
local RANGED_CONE_LANE_SPREAD = 3
local CONE_STAGING_SAFETY_BUFFER = 2

local DEBUG_DIR = MOD_NAME
local DEBUG_FILES = {
  events = DEBUG_DIR .. "/events.jsonl",
  snapshot = DEBUG_DIR .. "/latest-snapshot.json",
  arena_manifest = DEBUG_DIR .. "/arena-manifest.json"
}
local DEBUG_RECENT_EVENT_LIMIT = 32
local DEBUG_SCENARIO_EVENT_LIMIT = 512
local DEBUG_STATUS_EVENT_LIMIT = 10
local DEBUG_OVERLAY_CANDIDATE_LIMIT = 8
local DEBUG_OVERLAY_GROUP_LIMIT = 16
local DEBUG_OVERLAY_SITE_LIMIT = 8
local DEBUG_OVERLAY_VIEW_RADIUS = 96
local DEBUG_ARENA_SURFACE_NAME = "abt-debug-arena"
local DEBUG_ARENA_TILE_HALF_SIZE = 64

local WALL_FILTER = {"wall", "gate"}
local TURRET_FILTER = {"ammo-turret", "electric-turret", "fluid-turret"}
local CARDINAL_SIDES = {
  {name = "north", dx = 0, dy = -1},
  {name = "east", dx = 1, dy = 0},
  {name = "south", dx = 0, dy = 1},
  {name = "west", dx = -1, dy = 0}
}

DEBUG_EVENT_NAMES = {
  group_registered = true,
  arena_wave_spawned = true,
  contact_found = true,
  wall_network_scanned = true,
  candidates_scored = true,
  attack_selected = true,
  flank_waypoint_set = true,
  siege_site_selected = true,
  support_mode_selected = true,
  support_group_created = true,
  support_position_rejected = true,
  standoff_position_selected = true,
  breach_pressure_detected = true,
  breach_pressure_lost = true,
  breach_progress_updated = true,
  breach_assault_planned = true,
  turret_priority_selected = true,
  melee_split_created = true,
  reserve_group_created = true,
  ranged_cone_group_created = true,
  ranged_cone_lane_set = true,
  support_followup_started = true,
  flame_lane_set = true,
  fire_hazard_avoided = true,
  open_entry_taken = true,
  interior_target_selected = true,
  wall_target_after_breach = true,
  breach_reused = true,
  coverage_violation = true,
  command_reasserted = true,
  unsafe_rally_replanned = true,
  state_stalled = true,
  support_mode_replanned = true,
  entry_progress_updated = true,
  fallback_issued = true,
  group_cleanup = true
}

count_open_breach_segments = nil
get_site_for_record = nil
process_debug_arena_waves = nil
ensure_entry_traversed = nil
require_admin_or_server = nil
parse_command_parameter = nil
write_manual_dump = nil
set_debug_enabled = nil
clear_debug_runtime = nil
get_runtime_group_diagnostics = nil
find_covering_turrets = nil
sample_line_positions = nil
serialize_turret_sources = nil
clear_command = nil
start_fallback_attack = nil
runtime_ext = {}
arena_runtime = nil
DEBUG_SCENARIOS = {
  ["wall-open"] = {
    name = "wall-open",
    spawn_position = {x = -16, y = 0},
    observe_position = {x = -28, y = 0},
    target_position = {x = 0, y = 0},
    walls = {
      {from = {x = 0, y = -10}, to = {x = 0, y = 10}}
    },
    turrets = {},
    units = {
      {name = "small-biter", count = 8},
      {name = "medium-biter", count = 4}
    },
    expected_behavior = "Direct attack after the first wall contact without any flank waypoint.",
    expected_event_sequence = {
      "group_registered",
      "contact_found",
      "wall_network_scanned",
      "candidates_scored",
      "attack_selected"
    }
  },
  ["wall-covered-flank"] = {
    name = "wall-covered-flank",
    spawn_position = {x = -16, y = -10},
    observe_position = {x = -28, y = -10},
    target_position = {x = 0, y = -10},
    walls = {
      {from = {x = 0, y = -22}, to = {x = 0, y = 18}}
    },
    turrets = {
      {position = {x = 6, y = -8}, ammo = 200}
    },
    units = {
      {name = "small-biter", count = 8},
      {name = "medium-biter", count = 4}
    },
    expected_behavior = "The front contact is turret-covered, so the group should flank along the wall before attacking.",
    expected_event_sequence = {
      "group_registered",
      "contact_found",
      "wall_network_scanned",
      "candidates_scored",
      "flank_waypoint_set",
      "attack_selected"
    }
  },
  ["closed-ring"] = {
    name = "closed-ring",
    spawn_position = {x = -18, y = 0},
    observe_position = {x = -30, y = 0},
    target_position = {x = 4, y = 0},
    walls = {
      {from = {x = 0, y = -8}, to = {x = 12, y = -8}},
      {from = {x = 12, y = -8}, to = {x = 12, y = 8}},
      {from = {x = 12, y = 8}, to = {x = 0, y = 8}},
      {from = {x = 0, y = 8}, to = {x = 0, y = -8}}
    },
    turrets = {
      {position = {x = 8, y = -4}, ammo = 200},
      {position = {x = 8, y = 4}, ammo = 200}
    },
    units = {
      {name = "medium-biter", count = 10},
      {name = "big-biter", count = 4}
    },
    expected_behavior = "The closed, fully covered wall should produce a shared siege site instead of a direct frontal attack.",
    expected_event_sequence = {
      "group_registered",
      "contact_found",
      "wall_network_scanned",
      "candidates_scored",
      "siege_site_selected",
      "attack_selected"
    }
  },
  ["spitter-siege"] = {
    name = "spitter-siege",
    spawn_position = {x = -18, y = 2},
    observe_position = {x = -30, y = 2},
    target_position = {x = 4, y = 0},
    walls = {
      {from = {x = 0, y = -8}, to = {x = 12, y = -8}},
      {from = {x = 12, y = -8}, to = {x = 12, y = 8}},
      {from = {x = 12, y = 8}, to = {x = 0, y = 8}},
      {from = {x = 0, y = 8}, to = {x = 0, y = -8}}
    },
    turrets = {
      {position = {x = 8, y = -4}, ammo = 200},
      {position = {x = 8, y = 4}, ammo = 200}
    },
    units = {
      {name = "small-spitter", count = 6},
      {name = "medium-spitter", count = 4}
    },
    expected_behavior = "Spitters should hold a safe standoff position and widen the breach across multiple wall segments before advancing.",
    expected_event_sequence = {
      "group_registered",
      "contact_found",
      "wall_network_scanned",
      "candidates_scored",
      "siege_site_selected",
      "standoff_position_selected",
      "support_group_created",
      "attack_selected"
    }
  },
  ["mixed-breach-siege"] = {
    name = "mixed-breach-siege",
    spawn_position = {x = -18, y = 2},
    observe_position = {x = -30, y = 2},
    target_position = {x = 4, y = 0},
    walls = {
      {from = {x = 0, y = -8}, to = {x = 12, y = -8}},
      {from = {x = 12, y = -8}, to = {x = 12, y = 8}},
      {from = {x = 12, y = 8}, to = {x = 0, y = 8}},
      {from = {x = 0, y = 8}, to = {x = 0, y = -8}}
    },
    turrets = {
      {position = {x = 8, y = -4}, ammo = 200},
      {position = {x = 8, y = 4}, ammo = 200}
    },
    structures = {
      {name = "radar", position = {x = 10, y = 0}},
      {name = "steel-chest", position = {x = 11, y = -2}},
      {name = "steel-chest", position = {x = 11, y = 2}}
    },
    units = {
      {name = "behemoth-biter", count = 12},
      {name = "big-spitter", count = 10}
    },
    expected_behavior = "Spitters should widen the breach from a safe standoff position while biters wait outside until the opening is at least two to three wall segments wide.",
    expected_event_sequence = {
      "group_registered",
      "contact_found",
      "wall_network_scanned",
      "candidates_scored",
      "support_mode_selected",
      "standoff_position_selected",
      "support_group_created",
      "siege_site_selected",
      "breach_assault_planned",
      "interior_target_selected"
    }
  },
  ["mixed-turret-breach"] = {
    name = "mixed-turret-breach",
    spawn_position = {x = -18, y = 0},
    observe_position = {x = -36, y = 0},
    target_position = {x = 48, y = 0},
    walls = {
      {from = {x = 0, y = -10}, to = {x = 48, y = -10}},
      {from = {x = 48, y = -10}, to = {x = 48, y = 10}},
      {from = {x = 48, y = 10}, to = {x = 0, y = 10}},
      {from = {x = 0, y = 10}, to = {x = 0, y = -10}}
    },
    turrets = {
      {name = "gun-turret", position = {x = 6, y = -5}, ammo = 200},
      {name = "gun-turret", position = {x = 6, y = 0}, ammo = 200},
      {name = "gun-turret", position = {x = 6, y = 5}, ammo = 200}
    },
    units = {
      {name = "medium-biter", count = 16},
      {name = "big-biter", count = 6},
      {name = "small-spitter", count = 6},
      {name = "medium-spitter", count = 4}
    },
    expected_behavior = "Front gun-turret coverage should make the group walk around the rectangle and choose the uncovered rear wall before starting the breach.",
    expected_event_sequence = {
      "group_registered",
      "contact_found",
      "wall_network_scanned",
      "candidates_scored",
      "flank_waypoint_set",
      "attack_selected"
    }
  },
  ["flame-turret-breach"] = {
    name = "flame-turret-breach",
    spawn_position = {x = -20, y = 2},
    observe_position = {x = -34, y = 2},
    target_position = {x = 16, y = 0},
    walls = {
      {from = {x = 0, y = -10}, to = {x = 28, y = -10}},
      {from = {x = 28, y = -10}, to = {x = 28, y = 10}},
      {from = {x = 28, y = 10}, to = {x = 0, y = 10}},
      {from = {x = 0, y = 10}, to = {x = 0, y = -10}}
    },
    turrets = {
      {name = "flamethrower-turret", position = {x = 16, y = -4}, direction = defines.direction.west, fuel_name = "light-oil"},
      {name = "flamethrower-turret", position = {x = 16, y = 4}, direction = defines.direction.west, fuel_name = "light-oil"},
      {name = "gun-turret", position = {x = 22, y = 0}, ammo = 200}
    },
    units = {
      {name = "medium-biter", count = 18},
      {name = "big-biter", count = 6},
      {name = "small-spitter", count = 8},
      {name = "medium-spitter", count = 4}
    },
    expected_support_mode = "cone-siege",
    expected_behavior = "Flamethrower turrets should force a pre-breach ranged cone that forms outside flame range first, then converges on the same wall section while melee waits for a breach.",
    expected_event_sequence = {
      "group_registered",
      "contact_found",
      "wall_network_scanned",
      "candidates_scored",
      "support_mode_selected",
      "ranged_cone_group_created",
      "ranged_cone_lane_set",
      "siege_site_selected",
      "breach_assault_planned",
      "turret_priority_selected",
      "flame_lane_set"
    }
  },
  ["breach-reuse"] = {
    name = "breach-reuse",
    spawn_position = {x = -20, y = 0},
    observe_position = {x = -30, y = 0},
    target_position = {x = 11, y = 0},
    walls = {
      {from = {x = 0, y = -10}, to = {x = 18, y = -10}},
      {from = {x = 18, y = -10}, to = {x = 18, y = 10}},
      {from = {x = 18, y = 10}, to = {x = 0, y = 10}},
      {from = {x = 0, y = -10}, to = {x = 0, y = -5}},
      {from = {x = 0, y = 5}, to = {x = 0, y = 10}}
    },
    turrets = {
      {name = "gun-turret", position = {x = 8, y = -4}, ammo = 200},
      {name = "gun-turret", position = {x = 8, y = 4}, ammo = 200}
    },
    structures = {
      {name = "radar", position = {x = 13, y = 0}},
      {name = "steel-chest", position = {x = 16, y = -2}},
      {name = "steel-chest", position = {x = 16, y = 2}}
    },
    open_breach_positions = {
      {x = 0, y = -4},
      {x = 0, y = -3},
      {x = 0, y = -2},
      {x = 0, y = -1},
      {x = 0, y = 0},
      {x = 0, y = 1},
      {x = 0, y = 2},
      {x = 0, y = 3},
      {x = 0, y = 4}
    },
    waves = {
      {
        delay = 0,
        spawn_position = {x = -20, y = 0},
        target_position = {x = 11, y = 0},
        units = {
          {name = "medium-biter", count = 10},
          {name = "big-biter", count = 4},
          {name = "small-spitter", count = 4}
        }
      },
      {
        delay = 240,
        spawn_position = {x = 9, y = 18},
        target_position = {x = 11, y = 0},
        units = {
          {name = "medium-biter", count = 8},
          {name = "big-biter", count = 4},
          {name = "small-spitter", count = 3}
        }
      }
    },
    reuse_site = true,
    expected_reuse_wave_count = 2,
    expected_behavior = "Wave one should move through the already open breach before prioritizing interior gun turrets, and wave two should reuse that same opening instead of starting a fresh wall attack.",
    expected_event_sequence = {
      "arena_wave_spawned",
      "group_registered",
      "open_entry_taken",
      "interior_target_selected",
      "arena_wave_spawned",
      "breach_reused"
    }
  }
}

local function copy_position(position)
  return {x = position.x, y = position.y}
end

local function copy_positions(positions)
  if not positions then
    return nil
  end

  local copy = {}
  for index = 1, #positions do
    copy[index] = copy_position(positions[index])
  end
  return copy
end

local function position_key(position)
  return string.format("%.2f:%.2f", position.x, position.y)
end

local function distance_sq(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return dx * dx + dy * dy
end

local function offset_position(position, dx, dy)
  return {x = position.x + dx, y = position.y + dy}
end

local function normalized_direction(from_position, to_position)
  local dx = to_position.x - from_position.x
  local dy = to_position.y - from_position.y
  local length = math.sqrt(dx * dx + dy * dy)

  if length == 0 then
    return 0, 0
  end

  return dx / length, dy / length
end

local function round_number(value, digits)
  local scale = 10 ^ (digits or 0)
  return math.floor(value * scale + 0.5) / scale
end

local function format_number(value)
  if value == nil then
    return "-"
  end

  return string.format("%.1f", value)
end

local function ensure_globals()
  storage.group_ai = storage.group_ai or {}
  storage.group_queue = storage.group_queue or {}
  storage.group_queue_index = storage.group_queue_index or 1
  storage.siege_sites = storage.siege_sites or {}
  storage.debug = storage.debug or {}
  storage.debug.enabled_players = storage.debug.enabled_players or {}
  storage.debug.recent_events = storage.debug.recent_events or {}
  storage.debug.scenario_events = storage.debug.scenario_events or {}
  storage.debug.server_capture = storage.debug.server_capture or false
  storage.debug.arena = storage.debug.arena or nil
end

local function sanitize_debug_players()
  local players = {}

  for player_index in pairs(storage.debug.enabled_players) do
    local player = game.get_player(player_index)
    if player and player.valid then
      players[#players + 1] = player_index
    else
      storage.debug.enabled_players[player_index] = nil
    end
  end

  table.sort(players)
  return players
end

local function get_debug_player_indices()
  ensure_globals()
  local players = sanitize_debug_players()
  if storage.debug.server_capture then
    players[#players + 1] = 0
  end
  return players
end

local function get_overlay_player_indices()
  ensure_globals()
  return sanitize_debug_players()
end

local function get_overlay_player_contexts()
  ensure_globals()
  local player_indices = sanitize_debug_players()
  local contexts = {}

  for index = 1, #player_indices do
    local player = game.get_player(player_indices[index])
    if player and player.valid and player.surface then
      contexts[#contexts + 1] = {
        player_index = player.index,
        surface_index = player.surface.index,
        position = copy_position(player.position)
      }
    end
  end

  return contexts
end

local function overlay_surface_is_visible(contexts, surface_index)
  for index = 1, #contexts do
    if contexts[index].surface_index == surface_index then
      return true
    end
  end

  return false
end

local function overlay_position_is_visible(contexts, surface_index, position)
  if not position then
    return false
  end

  local view_radius_sq = DEBUG_OVERLAY_VIEW_RADIUS * DEBUG_OVERLAY_VIEW_RADIUS
  for index = 1, #contexts do
    local context = contexts[index]
    if context.surface_index == surface_index and distance_sq(context.position, position) <= view_radius_sq then
      return true
    end
  end

  return false
end

local function is_debug_capture_enabled()
  ensure_globals()

  if storage.debug.server_capture then
    return true
  end

  for _ in pairs(storage.debug.enabled_players) do
    return true
  end

  return false
end

local function clear_debug_overlay()
  rendering.clear(MOD_NAME)
end

local function json_write(path, data, append)
  helpers.write_file(path, helpers.table_to_json(data), append)
end

local function append_jsonl(path, data)
  helpers.write_file(path, helpers.table_to_json(data) .. "\n", true)
end

local function trim_recent_events()
  while #storage.debug.recent_events > DEBUG_RECENT_EVENT_LIMIT do
    table.remove(storage.debug.recent_events, 1)
  end
end

local function trim_scenario_events(scenario_name)
  if not scenario_name then
    return
  end

  local events = storage.debug.scenario_events[scenario_name]
  if not events then
    return
  end

  while #events > DEBUG_SCENARIO_EVENT_LIMIT do
    table.remove(events, 1)
  end
end

local function serialize_position(position)
  if not position then
    return nil
  end

  return {
    x = round_number(position.x, 2),
    y = round_number(position.y, 2)
  }
end

local function serialize_positions(positions)
  if not positions then
    return nil
  end

  local serialized = {}
  for index = 1, #positions do
    serialized[index] = serialize_position(positions[index])
  end
  return serialized
end

local function serialize_bounds(bounds)
  if not bounds then
    return nil
  end

  return {
    left_top = serialize_position(bounds.left_top),
    right_bottom = serialize_position(bounds.right_bottom)
  }
end

runtime_ext.serialize_area_from_center = function(position, radius)
  return serialize_bounds({
    left_top = {
      x = position.x - radius,
      y = position.y - radius
    },
    right_bottom = {
      x = position.x + radius,
      y = position.y + radius
    }
  })
end

local function average_positions(positions)
  if not positions or #positions == 0 then
    return nil
  end

  local total_x = 0
  local total_y = 0
  for index = 1, #positions do
    total_x = total_x + positions[index].x
    total_y = total_y + positions[index].y
  end

  return {
    x = total_x / #positions,
    y = total_y / #positions
  }
end

local function get_side_definition(side_name)
  for index = 1, #CARDINAL_SIDES do
    if CARDINAL_SIDES[index].name == side_name then
      return CARDINAL_SIDES[index]
    end
  end

  return nil
end

local function append_unique_id(list, value)
  if not (list and value) then
    return
  end

  for index = 1, #list do
    if list[index] == value then
      return
    end
  end

  list[#list + 1] = value
end

local function remove_id_from_list(list, value)
  if not (list and value) then
    return
  end

  local index = 1
  while index <= #list do
    if list[index] == value then
      table.remove(list, index)
    else
      index = index + 1
    end
  end
end

local function get_group(record)
  if record.group and record.group.valid and record.group.force.valid and record.group.force.name == "enemy" then
    return record.group
  end

  return nil
end

local function normalize_group_record(record)
  if not record then
    return nil
  end

  record.role = record.role or "main"
  record.state = record.state or "tracking"
  record.replans = tonumber(record.replans) or 0
  if record.support_spawned == nil then
    record.support_spawned = false
  end

  record.target_turret_position = record.target_turret_position and copy_position(record.target_turret_position) or nil
  record.site_entry_position = record.site_entry_position and copy_position(record.site_entry_position) or nil
  record.inside_rally_position = record.inside_rally_position and copy_position(record.inside_rally_position) or nil
  record.exploit_position = record.exploit_position and copy_position(record.exploit_position) or nil
  record.approach_side = record.approach_side or nil
  record.support_mode = record.support_mode or "none"
  record.support_rejection_reason = record.support_rejection_reason or nil
  record.support_group_ids = record.support_group_ids or {}
  record.debug_registered = record.debug_registered == true
  record.wave_index = tonumber(record.wave_index) or nil
  record.lane_positions = copy_positions(record.lane_positions)
  record.hazard_positions = copy_positions(record.hazard_positions)
  record.breach_wait_started_tick = tonumber(record.breach_wait_started_tick) or nil
  record.breach_replan_used = record.breach_replan_used == true
  record.reserve_registered = record.reserve_registered == true
  record.entry_open = record.entry_open == true
  record.last_state_name = record.last_state_name or record.state
  record.state_since_tick = tonumber(record.state_since_tick) or game.tick
  record.last_meaningful_progress_tick = tonumber(record.last_meaningful_progress_tick) or record.activated_tick or game.tick
  record.progress_anchor_position = record.progress_anchor_position and copy_position(record.progress_anchor_position) or nil
  record.last_stalled_state = record.last_stalled_state or nil
  record.entry_progress_stage = record.entry_progress_stage or nil
  record.entry_progress = tonumber(record.entry_progress) or nil
  record.last_breach_pressure_lost_tick = tonumber(record.last_breach_pressure_lost_tick) or nil

  local group = get_group(record)
  if group then
    record.surface_name = group.surface.name
    record.last_position = copy_position(group.position)
    record.progress_anchor_position = record.progress_anchor_position or copy_position(group.position)
  elseif record.last_position then
    record.last_position = copy_position(record.last_position)
    record.progress_anchor_position = record.progress_anchor_position or copy_position(record.last_position)
  end

  return record
end

local function normalize_site(site)
  if not site then
    return nil
  end

  site.target_position = site.target_position and copy_position(site.target_position) or nil
  site.rally_position = site.rally_position and copy_position(site.rally_position) or nil
  site.support_position = site.support_position and copy_position(site.support_position) or nil
  site.support_mode = site.support_mode or "none"
  site.breach_positions = copy_positions(site.breach_positions)
  site.breach_attack_order = copy_positions(site.breach_attack_order)
  site.entry_open = site.entry_open == true
  site.entry_clear = site.entry_clear == true
  site.entry_position = site.entry_position and copy_position(site.entry_position) or nil
  site.inside_rally_position = site.inside_rally_position and copy_position(site.inside_rally_position) or nil
  site.exploit_position = site.exploit_position and copy_position(site.exploit_position) or nil
  site.seeded_inside_rally_position = site.seeded_inside_rally_position and copy_position(site.seeded_inside_rally_position) or nil
  site.seeded_exploit_position = site.seeded_exploit_position and copy_position(site.seeded_exploit_position) or nil
  site.approach_side = site.approach_side or nil
  site.support_rejection_reason = site.support_rejection_reason or nil
  site.cone_lane_positions = copy_positions(site.cone_lane_positions)
  site.assault_targets = site.assault_targets or {}
  site.active_flame_turrets = site.active_flame_turrets or {}
  site.flame_hazard_bounds = site.flame_hazard_bounds or nil
  site.assault_group_ids = site.assault_group_ids or {}
  site.cone_group_ids = site.cone_group_ids or {}
  site.reserve_group_ids = site.reserve_group_ids or {}
  site.last_breach_pressure_tick = tonumber(site.last_breach_pressure_tick) or nil
  site.wave_count = tonumber(site.wave_count) or 0
  site.probe_unit_name = site.probe_unit_name or UNIT_PROBE_FALLBACK
  return site
end

local function rebuild_group_queue()
  local rebuilt_queue = {}
  local seen = {}

  for index = 1, #storage.group_queue do
    local record_id = storage.group_queue[index]
    if record_id and storage.group_ai[record_id] and not seen[record_id] then
      rebuilt_queue[#rebuilt_queue + 1] = record_id
      seen[record_id] = true
    end
  end

  for record_id in pairs(storage.group_ai) do
    if not seen[record_id] then
      rebuilt_queue[#rebuilt_queue + 1] = record_id
    end
  end

  storage.group_queue = rebuilt_queue
  if #rebuilt_queue == 0 or storage.group_queue_index < 1 or storage.group_queue_index > #rebuilt_queue then
    storage.group_queue_index = 1
  end
end

local function repair_runtime_state()
  ensure_globals()

  for _, record in pairs(storage.group_ai) do
    normalize_group_record(record)
  end

  for _, site in pairs(storage.siege_sites) do
    normalize_site(site)
  end

  rebuild_group_queue()
end

local function purge_surface_runtime_state(surface_index)
  for record_id, record in pairs(storage.group_ai) do
    local group = get_group(record)
    local record_surface_index

    if group then
      record_surface_index = group.surface.index
    elseif record.surface_name and game.surfaces[record.surface_name] then
      record_surface_index = game.surfaces[record.surface_name].index
    end

    if record_surface_index == surface_index then
      if group then
        if group.valid and group.is_unit_group and group.is_script_driven then
          group.set_autonomous()
        end
      end
      storage.group_ai[record_id] = nil
    end
  end

  for site_key, site in pairs(storage.siege_sites) do
    if site.surface_index == surface_index then
      storage.siege_sites[site_key] = nil
    end
  end

  rebuild_group_queue()
end

local function count_group_members(group)
  local count = 0
  local members = group.members

  for index = 1, #members do
    if members[index].valid then
      count = count + 1
    end
  end

  return count
end

local function get_candidate_debug_score(candidate)
  local gate_priority = (candidate.is_gate and candidate.cover_count == 0) and 0 or 1
  return gate_priority * 100000000
    + candidate.cover_count * 1000000
    + math.floor(candidate.distance_sq * 100 + 0.5) * 10
    + candidate.density
end

local function serialize_site(site)
  local surface = game.surfaces[site.surface_index]
  local breach_open_segments = 0
  if surface and site.breach_positions then
    breach_open_segments = count_open_breach_segments(surface, site.defense_force_name, site.breach_positions)
  end

  return {
    key = site.key,
    surface = surface and surface.name or tostring(site.surface_index),
    target_position = serialize_position(site.target_position),
    approach_side = site.approach_side,
    rally_position = serialize_position(site.rally_position),
    support_position = serialize_position(site.support_position),
    support_mode = site.support_mode,
    support_rejection_reason = site.support_rejection_reason,
    cone_lane_positions = serialize_positions(site.cone_lane_positions),
    breach_positions = serialize_positions(site.breach_positions),
    breach_attack_order = serialize_positions(site.breach_attack_order),
    breach_required_segments = site.breach_required_segments,
    breach_open_segments = breach_open_segments,
    entry_open = site.entry_open,
    entry_clear = site.entry_clear,
    entry_position = serialize_position(site.entry_position),
    inside_rally_position = serialize_position(site.inside_rally_position),
    exploit_position = serialize_position(site.exploit_position),
    assault_targets = site.assault_targets,
    active_flame_turrets = site.active_flame_turrets,
    reserve_group_ids = site.reserve_group_ids,
    assault_group_ids = site.assault_group_ids,
    cone_group_ids = site.cone_group_ids,
    flame_hazard_bounds = serialize_bounds(site.flame_hazard_bounds),
    defense_force_name = site.defense_force_name,
    last_breach_pressure_tick = site.last_breach_pressure_tick,
    breach_pressure_active = site.last_breach_pressure_tick ~= nil
      and (game.tick - site.last_breach_pressure_tick) <= STALL_TIMEOUT_TICKS,
    wave_count = site.wave_count,
    expires_tick = site.expires_tick
  }
end

local function serialize_record(record)
  local group = get_group(record)
  local diagnostics = get_runtime_group_diagnostics and get_runtime_group_diagnostics(record, group) or {}

  return {
    id = record.id,
    role = record.role,
    parent_id = record.parent_id,
    surface = group and group.surface.name or record.surface_name,
    scenario = record.scenario,
    wave_index = record.wave_index,
    state = record.state,
    replans = record.replans,
    support_group_id = record.support_group_id,
    siege_site_id = record.siege_site_id,
    member_count = group and count_group_members(group) or 0,
    activated_tick = record.activated_tick,
    last_seen_tick = record.last_seen_tick,
    state_since_tick = record.state_since_tick,
    state_duration_ticks = diagnostics.state_duration_ticks,
    last_meaningful_progress_tick = record.last_meaningful_progress_tick,
    group_position = serialize_position(group and group.position or record.last_position),
    in_turret_coverage = diagnostics.in_turret_coverage,
    covering_turret_count = diagnostics.covering_turret_count,
    coverage_sources = diagnostics.coverage_sources,
    in_flame_hazard = diagnostics.in_flame_hazard,
    hazard_score = diagnostics.hazard_score,
    entry_progress = diagnostics.entry_progress,
    breach_pressure_active = diagnostics.breach_pressure_active,
    target_position = serialize_position(record.target_position),
    approach_side = record.approach_side,
    rally_position = serialize_position(record.rally_position),
    support_position = serialize_position(record.support_position),
    support_mode = record.support_mode,
    support_rejection_reason = record.support_rejection_reason,
    support_group_ids = record.support_group_ids,
    site_entry_position = serialize_position(record.site_entry_position),
    inside_rally_position = serialize_position(record.inside_rally_position),
    exploit_position = serialize_position(record.exploit_position),
    command_kind = record.command_kind,
    command_distraction = record.command_distraction,
    command_status = record.command_status,
    command_result = record.command_result,
    command_target_position = serialize_position(record.command_target_position),
    group_state = group and group.is_unit_group and group.state or nil,
    script_command_preserved = record.command_status == "active",
    last_contact_position = serialize_position(record.last_contact_position),
    breach_positions = serialize_positions(record.breach_positions),
    breach_attack_order = serialize_positions(record.breach_attack_order),
    breach_required_segments = record.breach_required_segments,
    breach_open_segments = record.breach_open_segments,
    breach_wait_started_tick = record.breach_wait_started_tick,
    breach_replan_used = record.breach_replan_used,
    waiting_for_breach = record.waiting_for_breach,
    entry_open = record.entry_open,
    target_turret_name = record.target_turret_name,
    target_turret_position = serialize_position(record.target_turret_position),
    lane_index = record.lane_index,
    lane_positions = serialize_positions(record.lane_positions),
    hazard_positions = serialize_positions(record.hazard_positions),
    selected_candidate_index = record.debug_selected_candidate_index,
    candidates = record.debug_candidates or {},
    analysis = record.debug_analysis,
    flank_waypoints = serialize_positions(record.flank_waypoints),
    entry_progress_stage = record.entry_progress_stage
  }
end

runtime_ext.serialize_visible_entity = function(entity)
  return {
    name = entity.name,
    type = entity.type,
    force = entity.force and entity.force.name or nil,
    unit_number = entity.unit_number,
    position = serialize_position(entity.position),
    health = entity.health,
    direction = entity.direction,
    status = entity.status,
    active = entity.active,
    destructible = entity.destructible
  }
end

local function write_latest_snapshot(reason)
  ensure_globals()

  local groups = {}
  local active_group_count = 0

  for _, record in pairs(storage.group_ai) do
    groups[#groups + 1] = serialize_record(record)
    if record.activated_tick or record.state ~= "tracking" then
      active_group_count = active_group_count + 1
    end
  end

  table.sort(groups, function(left, right)
    return left.id < right.id
  end)

  local siege_sites = {}
  for _, site in pairs(storage.siege_sites) do
    siege_sites[#siege_sites + 1] = serialize_site(site)
  end
  table.sort(siege_sites, function(left, right)
    return left.key < right.key
  end)

  local recent_events = {}
  for index = 1, #storage.debug.recent_events do
    recent_events[index] = storage.debug.recent_events[index]
  end

  json_write(DEBUG_FILES.snapshot, {
    tick = game.tick,
    reason = reason,
    debug_enabled_players = get_debug_player_indices(),
    tracked_group_count = #groups,
    active_group_count = active_group_count,
    siege_site_count = #siege_sites,
    groups = groups,
    siege_sites = siege_sites,
    recent_events = recent_events,
    arena = storage.debug.arena
  }, false)
end

local function write_arena_manifest()
  if storage.debug.arena then
    json_write(DEBUG_FILES.arena_manifest, storage.debug.arena, false)
  end
end

runtime_ext.get_recent_scenario_events = function(scenario_name)
  ensure_globals()

  if scenario_name and storage.debug.scenario_events[scenario_name] then
    local scenario_events = {}
    local stored_events = storage.debug.scenario_events[scenario_name]
    for index = 1, #stored_events do
      scenario_events[index] = stored_events[index]
    end
    return scenario_events
  end

  local events = {}
  for index = 1, #storage.debug.recent_events do
    local event = storage.debug.recent_events[index]
    if scenario_name == nil or event.scenario == scenario_name then
      events[#events + 1] = event
    end
  end

  return events
end

runtime_ext.event_sequence_matches = function(events, expected_sequence)
  local event_index = 1
  local matched = {}
  local missing = {}

  for expected_index = 1, #expected_sequence do
    local expected_event = expected_sequence[expected_index]
    while event_index <= #events and events[event_index].event ~= expected_event do
      event_index = event_index + 1
    end

    if event_index > #events then
      missing[#missing + 1] = expected_event
    else
      matched[#matched + 1] = expected_event
      event_index = event_index + 1
    end
  end

  return #missing == 0, matched, missing
end

runtime_ext.make_bridge_assertion = function(name, assertion_type, passed, expected, actual, evidence)
  return {
    name = name,
    type = assertion_type,
    passed = passed,
    expected = expected,
    actual = actual,
    evidence = evidence or {}
  }
end

local function record_debug_event(event_name, record, extra)
  if not DEBUG_EVENT_NAMES[event_name] then
    return
  end

  ensure_globals()

  local group = record and get_group(record) or nil
  local payload = {
    tick = game.tick,
    event = event_name,
    group_id = record and record.id or nil,
    surface = group and group.surface.name or (record and record.surface_name or nil),
    state = record and record.state or nil,
    reason = extra and extra.reason or nil,
    group_position = serialize_position(group and group.position or (record and record.last_position or nil)),
    target_position = serialize_position(extra and extra.target_position or (record and record.target_position or nil)),
    contact_position = serialize_position(extra and extra.contact_position or (record and record.last_contact_position or nil)),
    approach_side = extra and extra.approach_side or (record and record.approach_side or nil),
    support_mode = extra and extra.support_mode or (record and record.support_mode or nil),
    candidate_count = extra and extra.candidate_count or nil,
    selected_candidate_index = extra and extra.selected_candidate_index or (record and record.debug_selected_candidate_index or nil),
    replan_count = record and record.replans or nil,
    support_group_id = extra and extra.support_group_id or (record and record.support_group_id or nil),
    siege_site_id = extra and extra.siege_site_id or (record and record.siege_site_id or nil),
    scenario = extra and extra.scenario or (record and record.scenario or nil),
    wave_index = extra and extra.wave_index or (record and record.wave_index or nil),
    breach_open_segments = extra and extra.breach_open_segments or (record and record.breach_open_segments or nil),
    breach_required_segments = extra and extra.breach_required_segments or (record and record.breach_required_segments or nil),
    target_turret_name = extra and extra.target_turret_name or (record and record.target_turret_name or nil),
    target_turret_position = serialize_position(extra and extra.target_turret_position or (record and record.target_turret_position or nil)),
    assigned_melee_count = extra and extra.assigned_melee_count or nil,
    lane_index = extra and extra.lane_index or (record and record.lane_index or nil),
    hazard_score = extra and extra.hazard_score or nil,
    support_rejection_reason = extra and extra.support_rejection_reason or (record and record.support_rejection_reason or nil),
    entry_open = extra and extra.entry_open or (record and record.entry_open or nil),
    state_duration_ticks = record and record.state_since_tick and (game.tick - record.state_since_tick) or nil,
    last_meaningful_progress_tick = record and record.last_meaningful_progress_tick or nil,
    entry_progress = extra and extra.entry_progress or (record and record.entry_progress or nil),
    command_kind = extra and extra.command_kind or (record and record.command_kind or nil),
    command_distraction = extra and extra.command_distraction or (record and record.command_distraction or nil),
    command_target_position = serialize_position(extra and extra.command_target_position or (record and record.command_target_position or nil)),
    group_state = group and group.is_unit_group and group.state or nil,
    script_command_preserved = extra and extra.script_command_preserved or ((record and record.command_status == "active") or nil),
    coverage_sources = extra and extra.coverage_sources or nil,
    covering_turret_count = extra and extra.covering_turret_count or nil,
    in_turret_coverage = extra and extra.in_turret_coverage or nil,
    in_flame_hazard = extra and extra.in_flame_hazard or nil,
    breach_pressure_active = extra and extra.breach_pressure_active or nil
  }

  storage.debug.recent_events[#storage.debug.recent_events + 1] = payload
  trim_recent_events()
  if payload.scenario then
    storage.debug.scenario_events[payload.scenario] = storage.debug.scenario_events[payload.scenario] or {}
    storage.debug.scenario_events[payload.scenario][#storage.debug.scenario_events[payload.scenario] + 1] = payload
    trim_scenario_events(payload.scenario)
  end

  if is_debug_capture_enabled() then
    append_jsonl(DEBUG_FILES.events, payload)
  end
end

local function note_meaningful_progress(record, position)
  if not record then
    return
  end

  record.last_meaningful_progress_tick = game.tick
  if position then
    record.progress_anchor_position = copy_position(position)
  end
end

local function sync_record_runtime_state(record, group)
  if record.last_state_name ~= record.state then
    record.last_state_name = record.state
    record.state_since_tick = game.tick
    record.last_stalled_state = nil
    note_meaningful_progress(record, group and group.position or record.last_position)
  end

  if group and (
    not record.progress_anchor_position
    or distance_sq(group.position, record.progress_anchor_position) >= MEANINGFUL_PROGRESS_DISTANCE_SQ
  ) then
    note_meaningful_progress(record, group.position)
  end

  local site = get_site_for_record and get_site_for_record(record) or nil
  if site and group then
    local progress = runtime_ext.get_breach_entry_progress(site, group.position)
    record.entry_progress = progress
  else
    record.entry_progress = nil
  end
end

local function prebreach_safety_required(record)
  if not record or record.entry_open then
    return false
  end

  if record.role == "support" then
    return record.support_mode == "safe-standoff" or record.support_mode == "cone-siege"
  end

  return record.state == "flanking"
    or record.state == "rallying"
    or record.state == "breach-waiting"
    or record.waiting_for_breach == true
    or record.support_mode == "safe-standoff"
    or record.support_mode == "cone-siege"
end

local function emit_coverage_violation(record, position, reason, turrets)
  record_debug_event("coverage_violation", record, {
    reason = reason,
    target_position = position,
    in_turret_coverage = true,
    covering_turret_count = turrets and #turrets or 0,
    coverage_sources = serialize_turret_sources(turrets or {})
  })
end

local function handle_state_stall(record, group)
  if not record.last_meaningful_progress_tick then
    return false
  end

  local state = record.state
  if state ~= "support-moving"
    and state ~= "support-resetting"
    and state ~= "support-sieging"
    and state ~= "rallying"
    and state ~= "breach-waiting"
    and state ~= "flanking" then
    return false
  end

  if game.tick - record.last_meaningful_progress_tick < STALL_TIMEOUT_TICKS then
    return false
  end

  if record.last_stalled_state == state then
    return false
  end

  record.last_stalled_state = state
  record_debug_event("state_stalled", record, {
    reason = state,
    target_position = record.command_target_position or record.target_position,
    support_mode = record.support_mode,
    entry_progress = record.entry_progress
  })

  if record.role == "support" then
    local site = get_site_for_record(record)
    if not site then
      return false
    end

    local previous_mode = record.support_mode or "none"
    local next_mode = previous_mode
    if previous_mode == "safe-standoff" and site.cone_lane_positions and #site.cone_lane_positions > 0 then
      next_mode = "cone-siege"
      record.lane_positions = copy_positions(site.cone_lane_positions)
      record.lane_index = math.ceil(#site.cone_lane_positions / 2)
      record.support_position = copy_position(site.cone_lane_positions[record.lane_index])
    elseif previous_mode == "cone-siege" and site.support_position and #find_covering_turrets(group.surface, group.force, site.support_position) == 0 then
      next_mode = "safe-standoff"
      record.lane_positions = nil
      record.lane_index = nil
      record.support_position = copy_position(site.support_position)
    else
      next_mode = "none"
    end

    if next_mode ~= previous_mode then
      record.support_mode = next_mode
      site.support_mode = next_mode
      site.support_position = record.support_position and copy_position(record.support_position) or site.support_position
      clear_command(record)
      record_debug_event("support_mode_replanned", record, {
        reason = "state-stalled",
        support_mode = next_mode,
        target_position = record.support_position or record.target_position
      })
      note_meaningful_progress(record, group.position)
      if next_mode == "none" then
        start_fallback_attack(record, group, "support-stalled")
      else
        record.state = "support-moving"
      end
      return true
    end
  end

  if state == "rallying" or state == "breach-waiting" then
    clear_command(record)
    note_meaningful_progress(record, group.position)
  end

  return false
end

local function is_enemy_force(force)
  return force and force.valid and force.name == "enemy"
end

local function is_wall_like(entity, enemy_force)
  return entity.valid
    and (entity.type == "wall" or entity.type == "gate")
    and entity.force.valid
    and entity.force.index ~= enemy_force.index
end

local function is_combat_turret(entity, enemy_force)
  return entity.valid
    and entity.force.valid
    and entity.force.index ~= enemy_force.index
    and entity.type ~= "artillery-turret"
    and entity.prototype
    and entity.prototype.turret_range
    and entity.prototype.turret_range > 0
end

local function is_flamethrower_turret(entity)
  return entity and entity.valid and entity.name == "flamethrower-turret"
end

local function get_attack_range(entity)
  if not (entity and entity.valid and entity.prototype) then
    return 0
  end

  if entity.prototype.turret_range then
    return entity.prototype.turret_range
  end

  local attack_parameters = entity.prototype.attack_parameters
  if attack_parameters and attack_parameters.range then
    return attack_parameters.range
  end

  return 0
end

local function position_covered_by_turret(turret, position)
  local turret_range = get_attack_range(turret)
  return turret_range > 0 and distance_sq(turret.position, position) <= turret_range * turret_range
end

local function get_group_probe_unit_name(group)
  local members = group.members
  for index = 1, #members do
    local member = members[index]
    if member.valid then
      return member.name
    end
  end

  return UNIT_PROBE_FALLBACK
end

local function is_position_walkable(surface, position, probe_unit_name)
  return surface.can_place_entity({
    name = probe_unit_name,
    position = position,
    force = "enemy",
    build_check_type = defines.build_check_type.script
  })
end

find_covering_turrets = function(surface, enemy_force, position)
  local nearby_turrets = surface.find_entities_filtered({
    position = position,
    radius = 32,
    type = TURRET_FILTER
  })

  local covering_turrets = {}
  local max_cover_range = 0

  for index = 1, #nearby_turrets do
    local turret = nearby_turrets[index]
    if is_combat_turret(turret, enemy_force) then
      local turret_range = get_attack_range(turret)
      if turret_range > 0 and distance_sq(turret.position, position) <= turret_range * turret_range then
        covering_turrets[#covering_turrets + 1] = turret
        if turret_range > max_cover_range then
          max_cover_range = turret_range
        end
      end
    end
  end

  return covering_turrets, max_cover_range
end

serialize_turret_sources = function(turrets)
  local sources = {}
  for index = 1, #turrets do
    local turret = turrets[index]
    if turret.valid then
      sources[#sources + 1] = {
        name = turret.name,
        position = serialize_position(turret.position),
        range = round_number(get_attack_range(turret), 2)
      }
    end
  end
  return sources
end

local function get_position_fire_hazard(surface, position)
  if not (surface and position) then
    return 0, {}
  end

  local fires = surface.find_entities_filtered({
    position = position,
    radius = FLAME_HAZARD_RADIUS
  })
  local hazard_positions = {}
  local hazard_score = 0

  for index = 1, #fires do
    local entity = fires[index]
    if entity.valid and entity.type == "fire" then
      hazard_positions[#hazard_positions + 1] = copy_position(entity.position)
      hazard_score = hazard_score + math.max(1, math.floor((FLAME_HAZARD_RADIUS * FLAME_HAZARD_RADIUS - distance_sq(position, entity.position)) + 0.5))
    end
  end

  return hazard_score, hazard_positions
end

local function path_has_turret_coverage(surface, enemy_force, from_position, to_position)
  if not (surface and from_position and to_position) then
    return false, {}
  end

  local distance = math.sqrt(distance_sq(from_position, to_position))
  local sample_count = math.max(1, math.ceil(distance / COVERAGE_PATH_SAMPLE_SPACING))
  local samples = sample_line_positions(from_position, to_position, sample_count)
  local seen = {}
  local sources = {}

  for index = 1, #samples do
    local covering_turrets = find_covering_turrets(surface, enemy_force, samples[index])
    if #covering_turrets > 0 then
      for turret_index = 1, #covering_turrets do
        local turret = covering_turrets[turret_index]
        local turret_key = turret.valid and position_key(turret.position) or nil
        if turret.valid and turret_key and not seen[turret_key] then
          seen[turret_key] = true
          sources[#sources + 1] = turret
        end
      end
    end
  end

  return #sources > 0, sources
end

get_runtime_group_diagnostics = function(record, group)
  local diagnostics = {
    state_duration_ticks = record and record.state_since_tick and (game.tick - record.state_since_tick) or nil,
    in_turret_coverage = false,
    covering_turret_count = 0,
    coverage_sources = {},
    in_flame_hazard = false,
    hazard_score = 0,
    entry_progress = record and record.entry_progress or nil,
    breach_pressure_active = false
  }

  if record and record.siege_site_id then
    local site = storage.siege_sites[record.siege_site_id]
    if site and site.last_breach_pressure_tick then
      diagnostics.breach_pressure_active = (game.tick - site.last_breach_pressure_tick) <= STALL_TIMEOUT_TICKS
    end
  end

  if not group then
    return diagnostics
  end

  local covering_turrets = find_covering_turrets(group.surface, group.force, group.position)
  diagnostics.in_turret_coverage = #covering_turrets > 0
  diagnostics.covering_turret_count = #covering_turrets
  diagnostics.coverage_sources = serialize_turret_sources(covering_turrets)

  local hazard_score, hazards = get_position_fire_hazard(group.surface, group.position)
  diagnostics.in_flame_hazard = hazard_score > 0
  diagnostics.hazard_score = hazard_score
  if #hazards > 0 then
    diagnostics.hazard_positions = serialize_positions(hazards)
  end

  if record and record.siege_site_id then
    local site = storage.siege_sites[record.siege_site_id]
    if site then
      local progress = runtime_ext.get_breach_entry_progress(site, group.position)
      diagnostics.entry_progress = progress
    end
  end

  return diagnostics
end

local function choose_outside_sample(samples, reference_position)
  local best_sample
  local best_cover_count
  local best_distance

  for index = 1, #samples do
    local sample = samples[index]
    local sample_distance = distance_sq(sample.position, reference_position)
    local sample_cover_count = sample.cover_count or 0
    if not best_sample
      or sample_cover_count < best_cover_count
      or (sample_cover_count == best_cover_count and sample_distance < best_distance) then
      best_sample = sample
      best_cover_count = sample_cover_count
      best_distance = sample_distance
    end
  end

  return best_sample
end

local function compare_candidate_priority(left, right)
  local left_gate_priority = (left.is_gate and left.cover_count == 0) and 0 or 1
  local right_gate_priority = (right.is_gate and right.cover_count == 0) and 0 or 1

  if left_gate_priority ~= right_gate_priority then
    return left_gate_priority < right_gate_priority
  end

  if left.cover_count ~= right.cover_count then
    return left.cover_count < right.cover_count
  end

  if left.distance_sq ~= right.distance_sq then
    return left.distance_sq < right.distance_sq
  end

  return left.density < right.density
end

local function make_wall_node(entity)
  local node_key = entity.unit_number and tostring(entity.unit_number) or position_key(entity.position)
  return {
    key = node_key,
    entity = entity,
    position = copy_position(entity.position),
    is_gate = entity.type == "gate",
    neighbor_keys = {},
    neighbor_count = 0,
    density = 0,
    outside_samples = {},
    cover_count = 0,
    cover_turrets = {},
    max_cover_range = 0
  }
end

local function analyze_wall_network(group, start_entity)
  local surface = group.surface
  local enemy_force = group.force
  local probe_unit_name = get_group_probe_unit_name(group)
  local start_position = start_entity.position
  local max_network_distance_sq = WALL_NETWORK_RADIUS * WALL_NETWORK_RADIUS
  local nodes = {}
  local order = {}
  local queue = {start_entity}
  local queue_index = 1
  local truncated = false

  while queue_index <= #queue and #order < WALL_NETWORK_LIMIT do
    local entity = queue[queue_index]
    queue_index = queue_index + 1

    if entity.valid
      and entity.force.valid
      and entity.force.index == start_entity.force.index
      and (entity.type == "wall" or entity.type == "gate")
      and distance_sq(entity.position, start_position) <= max_network_distance_sq then
      local node_key = entity.unit_number and tostring(entity.unit_number) or position_key(entity.position)

      if not nodes[node_key] then
        local node = make_wall_node(entity)
        nodes[node_key] = node
        order[#order + 1] = node_key

        local neighbors = surface.find_entities_filtered({
          position = entity.position,
          radius = WALL_NEIGHBOR_RADIUS,
          type = WALL_FILTER
        })

        for neighbor_index = 1, #neighbors do
          local neighbor = neighbors[neighbor_index]
          if neighbor.valid
            and neighbor ~= entity
            and neighbor.force.valid
            and neighbor.force.index == start_entity.force.index
            and distance_sq(neighbor.position, start_position) <= max_network_distance_sq then
            local neighbor_key = neighbor.unit_number and tostring(neighbor.unit_number) or position_key(neighbor.position)
            node.neighbor_keys[neighbor_key] = true

            if not nodes[neighbor_key] then
              queue[#queue + 1] = neighbor
            end
          end
        end
      end
    end
  end

  if queue_index <= #queue then
    truncated = true
  end

  local candidates = {}
  local fully_covered = true
  local open_end_count = 0

  for order_index = 1, #order do
    local node = nodes[order[order_index]]
    local neighbor_count = 0

    for neighbor_key in pairs(node.neighbor_keys) do
      if nodes[neighbor_key] then
        neighbor_count = neighbor_count + 1
      else
        node.neighbor_keys[neighbor_key] = nil
      end
    end

    node.neighbor_count = neighbor_count
    node.density = neighbor_count + 1

    if neighbor_count <= 1 then
      open_end_count = open_end_count + 1
    end

    for side_index = 1, #CARDINAL_SIDES do
      local side = CARDINAL_SIDES[side_index]
      local sample_position = offset_position(node.position, side.dx * OUTSIDE_SAMPLE_OFFSET, side.dy * OUTSIDE_SAMPLE_OFFSET)
      if is_position_walkable(surface, sample_position, probe_unit_name) then
        local sample_cover_turrets = find_covering_turrets(surface, enemy_force, sample_position)
        node.outside_samples[#node.outside_samples + 1] = {
          direction = side.name,
          position = sample_position,
          cover_count = #sample_cover_turrets
        }
      end
    end

    if #node.outside_samples > 0 then
      node.cover_turrets, node.max_cover_range = find_covering_turrets(surface, enemy_force, node.position)
      node.cover_count = #node.cover_turrets
      if node.cover_count == 0 then
        fully_covered = false
      end
      candidates[#candidates + 1] = node
    else
      fully_covered = false
    end
  end

  return {
    nodes = nodes,
    order = order,
    truncated = truncated,
    closed = (not truncated) and #order >= 6 and open_end_count == 0,
    fully_covered = fully_covered,
    candidates = candidates,
    probe_unit_name = probe_unit_name
  }
end

local function get_nearest_wall(group)
  local nearby_entities = group.surface.find_entities_filtered({
    position = group.position,
    radius = CONTACT_RADIUS,
    type = WALL_FILTER
  })

  local best_wall
  local best_distance

  for index = 1, #nearby_entities do
    local entity = nearby_entities[index]
    if is_wall_like(entity, group.force) then
      local entity_distance = distance_sq(group.position, entity.position)
      if not best_distance or entity_distance < best_distance then
        best_wall = entity
        best_distance = entity_distance
      end
    end
  end

  return best_wall
end

local function make_candidate(node, reference_position)
  local outside_sample = choose_outside_sample(node.outside_samples, reference_position)
  if not outside_sample then
    return nil
  end

  return {
    key = node.key,
    entity = node.entity,
    position = node.position,
    is_gate = node.is_gate,
    outside_position = copy_position(outside_sample.position),
    outside_direction = outside_sample.direction,
    outside_samples = node.outside_samples,
    cover_count = node.cover_count,
    cover_turrets = node.cover_turrets,
    max_cover_range = node.max_cover_range,
    density = node.density,
    distance_sq = distance_sq(reference_position, node.position)
  }
end

local function build_debug_candidates(analysis, reference_position, selected_key)
  local debug_candidates = {}
  local selected_index

  for index = 1, #analysis.candidates do
    local candidate = make_candidate(analysis.candidates[index], reference_position)
    if candidate then
      debug_candidates[#debug_candidates + 1] = {
        position = serialize_position(candidate.position),
        outside_position = serialize_position(candidate.outside_position),
        is_gate = candidate.is_gate,
        turret_count = candidate.cover_count,
        distance_to_group = round_number(math.sqrt(candidate.distance_sq), 2),
        local_wall_density = candidate.density,
        score = get_candidate_debug_score(candidate),
        selected = candidate.key == selected_key
      }

      if candidate.key == selected_key then
        selected_index = #debug_candidates
      end
    end
  end

  return debug_candidates, selected_index
end

local function choose_contact_candidate(analysis, reference_position)
  local best_candidate
  local best_distance

  for index = 1, #analysis.candidates do
    local candidate = make_candidate(analysis.candidates[index], reference_position)
    if candidate and (not best_distance or candidate.distance_sq < best_distance) then
      best_candidate = candidate
      best_distance = candidate.distance_sq
    end
  end

  return best_candidate
end

local function choose_best_candidate(analysis, reference_position)
  local best_candidate

  for index = 1, #analysis.candidates do
    local candidate = make_candidate(analysis.candidates[index], reference_position)
    if candidate and (not best_candidate or compare_candidate_priority(candidate, best_candidate)) then
      best_candidate = candidate
    end
  end

  return best_candidate
end

local function build_wall_path(nodes, start_key, goal_key)
  if start_key == goal_key then
    return {start_key}
  end

  local queue = {start_key}
  local queue_index = 1
  local previous = {[start_key] = false}

  while queue_index <= #queue do
    local current_key = queue[queue_index]
    queue_index = queue_index + 1

    if current_key == goal_key then
      break
    end

    local node = nodes[current_key]
    if node then
      for neighbor_key in pairs(node.neighbor_keys) do
        if nodes[neighbor_key] and previous[neighbor_key] == nil then
          previous[neighbor_key] = current_key
          queue[#queue + 1] = neighbor_key
        end
      end
    end
  end

  if previous[goal_key] == nil then
    return nil
  end

  local path = {}
  local cursor = goal_key

  while cursor do
    table.insert(path, 1, cursor)
    cursor = previous[cursor]
  end

  return path
end

local function build_flank_waypoints(analysis, current_candidate, best_candidate)
  if current_candidate.key == best_candidate.key then
    return {}
  end

  local path = build_wall_path(analysis.nodes, current_candidate.key, best_candidate.key)
  if not path then
    return {copy_position(best_candidate.outside_position)}
  end

  local path_steps = #path - 1
  if path_steps <= 0 then
    return {}
  end

  local waypoint_count = math.min(MAX_FLANK_STEPS, math.max(1, path_steps))
  local waypoints = {}

  for step = 1, waypoint_count do
    local ratio = step / waypoint_count
    local path_index = math.floor(1 + path_steps * ratio + 0.5)
    if path_index > #path then
      path_index = #path
    end

    local path_node = analysis.nodes[path[path_index]]
    if path_node then
      local sample = choose_outside_sample(path_node.outside_samples, best_candidate.outside_position)
      if sample then
        local waypoint = copy_position(sample.position)
        if #waypoints == 0 or distance_sq(waypoints[#waypoints], waypoint) > 1 then
          waypoints[#waypoints + 1] = waypoint
        end
      end
    end
  end

  if #waypoints == 0 then
    waypoints[1] = copy_position(best_candidate.outside_position)
  elseif distance_sq(waypoints[#waypoints], best_candidate.outside_position) > 1 then
    if #waypoints < MAX_FLANK_STEPS then
      waypoints[#waypoints + 1] = copy_position(best_candidate.outside_position)
    else
      waypoints[#waypoints] = copy_position(best_candidate.outside_position)
    end
  end

  return waypoints
end

function runtime_ext.build_perimeter_flank_waypoints(analysis, current_candidate, best_candidate)
  if not (analysis and current_candidate and best_candidate and current_candidate.outside_position and best_candidate.outside_position) then
    return {}
  end

  local min_x, max_x, min_y, max_y
  for _, node in pairs(analysis.nodes or {}) do
    if node and node.position then
      min_x = min_x and math.min(min_x, node.position.x) or node.position.x
      max_x = max_x and math.max(max_x, node.position.x) or node.position.x
      min_y = min_y and math.min(min_y, node.position.y) or node.position.y
      max_y = max_y and math.max(max_y, node.position.y) or node.position.y
    end
  end

  if not (min_x and max_x and min_y and max_y) then
    return {}
  end

  local margin = math.max(
    OUTSIDE_SAMPLE_OFFSET + 3,
    (current_candidate.max_cover_range or 0) + 4,
    (best_candidate.max_cover_range or 0) + 4
  )
  local west_x = min_x - margin
  local east_x = max_x + margin
  local north_y = min_y - margin
  local south_y = max_y + margin
  local current = current_candidate.outside_position
  local best = best_candidate.outside_position
  local routes = {}

  if current_candidate.outside_direction == "west" and best_candidate.outside_direction == "east" then
    routes[1] = {
      {x = west_x, y = north_y},
      {x = east_x, y = north_y},
      copy_position(best)
    }
    routes[2] = {
      {x = west_x, y = south_y},
      {x = east_x, y = south_y},
      copy_position(best)
    }
  elseif current_candidate.outside_direction == "east" and best_candidate.outside_direction == "west" then
    routes[1] = {
      {x = east_x, y = north_y},
      {x = west_x, y = north_y},
      copy_position(best)
    }
    routes[2] = {
      {x = east_x, y = south_y},
      {x = west_x, y = south_y},
      copy_position(best)
    }
  elseif current_candidate.outside_direction == "north" and best_candidate.outside_direction == "south" then
    routes[1] = {
      {x = west_x, y = north_y},
      {x = west_x, y = south_y},
      copy_position(best)
    }
    routes[2] = {
      {x = east_x, y = north_y},
      {x = east_x, y = south_y},
      copy_position(best)
    }
  elseif current_candidate.outside_direction == "south" and best_candidate.outside_direction == "north" then
    routes[1] = {
      {x = west_x, y = south_y},
      {x = west_x, y = north_y},
      copy_position(best)
    }
    routes[2] = {
      {x = east_x, y = south_y},
      {x = east_x, y = north_y},
      copy_position(best)
    }
  elseif current_candidate.outside_direction == "west" and best_candidate.outside_direction == "west" then
    routes[1] = {
      {x = west_x, y = current.y},
      {x = west_x, y = best.y},
      copy_position(best)
    }
  elseif current_candidate.outside_direction == "east" and best_candidate.outside_direction == "east" then
    routes[1] = {
      {x = east_x, y = current.y},
      {x = east_x, y = best.y},
      copy_position(best)
    }
  elseif current_candidate.outside_direction == "north" and best_candidate.outside_direction == "north" then
    routes[1] = {
      {x = current.x, y = north_y},
      {x = best.x, y = north_y},
      copy_position(best)
    }
  elseif current_candidate.outside_direction == "south" and best_candidate.outside_direction == "south" then
    routes[1] = {
      {x = current.x, y = south_y},
      {x = best.x, y = south_y},
      copy_position(best)
    }
  else
    routes[1] = {
      copy_position(best)
    }
  end

  return routes
end

local function filter_safe_flank_waypoints(group, waypoints, preferred_position)
  if not group or #waypoints == 0 then
    return waypoints
  end

  local safe_waypoints = {}
  local previous_position = group.position
  for index = 1, #waypoints do
    local waypoint = waypoints[index]
    local path_covered = path_has_turret_coverage(group.surface, group.force, previous_position, waypoint)
    if #find_covering_turrets(group.surface, group.force, waypoint) == 0 and not path_covered then
      safe_waypoints[#safe_waypoints + 1] = waypoint
      previous_position = waypoint
    end
  end

  if #safe_waypoints == 0 then
    return {}
  end

  if preferred_position
    and distance_sq(safe_waypoints[#safe_waypoints], preferred_position) > 1
    and #find_covering_turrets(group.surface, group.force, preferred_position) == 0
    and not path_has_turret_coverage(group.surface, group.force, safe_waypoints[#safe_waypoints], preferred_position) then
    safe_waypoints[#safe_waypoints + 1] = copy_position(preferred_position)
  end

  return safe_waypoints
end

function runtime_ext.choose_safe_flank_route(group, route_sets, preferred_position)
  local best_route = {}
  local best_score

  for route_index = 1, #route_sets do
    local candidate_route = filter_safe_flank_waypoints(group, route_sets[route_index], preferred_position)
    if #candidate_route > 0 then
      local score = distance_sq(group.position, candidate_route[1])
      if not best_score or score < best_score then
        best_route = candidate_route
        best_score = score
      end
    end
  end

  return best_route
end

local function determine_breach_axis(analysis, candidate)
  local node = analysis.nodes[candidate.key]
  if not node then
    return "vertical"
  end

  local dx_total = 0
  local dy_total = 0

  for neighbor_key in pairs(node.neighbor_keys) do
    local neighbor = analysis.nodes[neighbor_key]
    if neighbor then
      dx_total = dx_total + math.abs(neighbor.position.x - candidate.position.x)
      dy_total = dy_total + math.abs(neighbor.position.y - candidate.position.y)
    end
  end

  if dx_total > dy_total then
    return "horizontal"
  end

  return "vertical"
end

local function build_breach_plan(analysis, candidate)
  local axis = determine_breach_axis(analysis, candidate)
  local nearby_nodes = {}

  for _, node in pairs(analysis.nodes) do
    local axis_delta
    local along_delta

    if axis == "vertical" then
      axis_delta = math.abs(node.position.x - candidate.position.x)
      along_delta = math.abs(node.position.y - candidate.position.y)
    else
      axis_delta = math.abs(node.position.y - candidate.position.y)
      along_delta = math.abs(node.position.x - candidate.position.x)
    end

    if axis_delta <= 0.25 and along_delta <= BREACH_TARGET_SEARCH_DISTANCE then
      nearby_nodes[#nearby_nodes + 1] = {
        key = node.key,
        position = copy_position(node.position),
        along = along_delta
      }
    end
  end

  table.sort(nearby_nodes, function(left, right)
    if left.along == right.along then
      if axis == "vertical" then
        return left.position.y < right.position.y
      end
      return left.position.x < right.position.x
    end

    return left.along < right.along
  end)

  local breach_positions = {}
  local attack_order = {}
  local selected = {}
  local target_count = math.min(DESIRED_BREACH_SEGMENTS, #nearby_nodes)

  for index = 1, target_count do
    local node = nearby_nodes[index]
    selected[node.key] = true
    breach_positions[#breach_positions + 1] = copy_position(node.position)
  end

  attack_order[1] = copy_position(candidate.position)
  for index = 1, #nearby_nodes do
    local node = nearby_nodes[index]
    if selected[node.key] and node.key ~= candidate.key then
      attack_order[#attack_order + 1] = copy_position(node.position)
    end
  end

  if #breach_positions == 0 then
    breach_positions[1] = copy_position(candidate.position)
    attack_order[1] = copy_position(candidate.position)
  end

  return {
    axis = axis,
    positions = breach_positions,
    attack_order = attack_order,
    required_segments = (#breach_positions >= MIN_BREACH_SEGMENTS)
      and math.min(DESIRED_BREACH_SEGMENTS, #breach_positions)
      or #breach_positions
  }
end

local function find_wall_entity_at(surface, defense_force_name, position)
  local walls = surface.find_entities_filtered({
    position = position,
    radius = BREACH_TARGET_RADIUS,
    type = WALL_FILTER,
    force = defense_force_name
  })

  for index = 1, #walls do
    local wall = walls[index]
    if wall.valid then
      return wall
    end
  end

  return nil
end

count_open_breach_segments = function(surface, defense_force_name, breach_positions)
  local open_segments = 0

  if not breach_positions then
    return open_segments
  end

  for index = 1, #breach_positions do
    if not find_wall_entity_at(surface, defense_force_name, breach_positions[index]) then
      open_segments = open_segments + 1
    end
  end

  return open_segments
end

local function breach_open_enough(surface, defense_force_name, breach_positions, required_segments)
  if not breach_positions or #breach_positions == 0 then
    return false, 0
  end

  local open_segments = count_open_breach_segments(surface, defense_force_name, breach_positions)
  return open_segments >= (required_segments or MIN_BREACH_SEGMENTS), open_segments
end

local function find_next_breach_target(surface, defense_force_name, breach_positions, attack_order)
  local ordered_positions = attack_order or breach_positions
  if not ordered_positions then
    return nil, nil
  end

  for index = 1, #ordered_positions do
    local position = ordered_positions[index]
    local wall = find_wall_entity_at(surface, defense_force_name, position)
    if wall then
      return wall, copy_position(position)
    end
  end

  return nil, nil
end

local function get_group_ranged_members(group)
  local ranged_members = {}
  local max_range = 0
  local members = group.members

  for index = 1, #members do
    local member = members[index]
    if member.valid then
      local attack_range = get_attack_range(member)
      if attack_range > 1.5 then
        ranged_members[#ranged_members + 1] = member
        if attack_range > max_range then
          max_range = attack_range
        end
      end
    end
  end

  return ranged_members, max_range
end

local function get_group_melee_members(group)
  local melee_members = {}
  local members = group.members

  for index = 1, #members do
    local member = members[index]
    if member.valid and get_attack_range(member) <= 1.5 then
      melee_members[#melee_members + 1] = member
    end
  end

  return melee_members
end

local function find_staging_position(surface, defense_force_name, target_position, outside_samples, probe_unit_name, min_distance, max_distance, max_target_distance)
  local best_safe_position
  local best_safe_distance
  local best_fallback_position
  local best_fallback_score

  for sample_index = 1, #outside_samples do
    local sample = outside_samples[sample_index]
    local direction_x, direction_y = normalized_direction(target_position, sample.position)

    if direction_x ~= 0 or direction_y ~= 0 then
      local distance = min_distance
      while distance <= max_distance do
        local candidate_position = {
          x = target_position.x + direction_x * distance,
          y = target_position.y + direction_y * distance
        }

        if is_position_walkable(surface, candidate_position, probe_unit_name) then
          local target_distance = math.sqrt(distance_sq(candidate_position, target_position))
          if not max_target_distance or target_distance <= max_target_distance then
            local covering_turrets = surface.find_entities_filtered({
              position = candidate_position,
              radius = 32,
              type = TURRET_FILTER,
              force = defense_force_name
            })

            local cover_count = 0
            for turret_index = 1, #covering_turrets do
              local turret = covering_turrets[turret_index]
              local turret_range = get_attack_range(turret)
              if turret.valid and turret_range > 0 and distance_sq(turret.position, candidate_position) <= turret_range * turret_range then
                cover_count = cover_count + 1
              end
            end

            if cover_count == 0 then
              local safe_distance = distance_sq(candidate_position, target_position)
              if not best_safe_distance or safe_distance < best_safe_distance then
                best_safe_position = copy_position(candidate_position)
                best_safe_distance = safe_distance
              end
            end

            local fallback_score = cover_count * 1000 + distance_sq(candidate_position, target_position)
            if not best_fallback_score or fallback_score < best_fallback_score then
              best_fallback_position = copy_position(candidate_position)
              best_fallback_score = fallback_score
            end
          end
        end

        distance = distance + 2
      end
    end
  end

  return best_safe_position, best_fallback_position
end

local function find_staging_positions(group, candidate, analysis)
  local defense_force_name = candidate.entity.force.name
  local ranged_members, ranged_range = get_group_ranged_members(group)
  local max_rally_distance = math.min(RALLY_HARD_MAX_DISTANCE, math.max(RALLY_BASE_MAX_DISTANCE, candidate.max_cover_range + 6))
  local preferred_side = candidate.outside_direction
  local preferred_samples = {}
  local support_mode = "none"
  local support_rejection_reason

  if preferred_side then
    for index = 1, #candidate.outside_samples do
      local sample = candidate.outside_samples[index]
      if sample.direction == preferred_side then
        preferred_samples[#preferred_samples + 1] = sample
      end
    end
  end

  if #preferred_samples == 0 then
    preferred_samples = candidate.outside_samples
    preferred_side = nil
  end

  local safe_rally_position, fallback_rally_position = find_staging_position(
    group.surface,
    defense_force_name,
    candidate.position,
    preferred_samples,
    analysis.probe_unit_name,
    RALLY_MIN_DISTANCE,
    max_rally_distance
  )
  local rally_position = safe_rally_position or fallback_rally_position

  if not rally_position then
    rally_position = copy_position(candidate.outside_position)
  end

  local support_position
  local cone_lane_positions
  if ranged_range > 1.5 then
    local safe_support_position, fallback_support_position = find_staging_position(
      group.surface,
      defense_force_name,
      candidate.position,
      preferred_samples,
      analysis.probe_unit_name,
      SUPPORT_STANDOFF_MIN_DISTANCE,
      math.max(2, math.floor(ranged_range - 0.5)),
      ranged_range - 0.5
    )

    local force_cone_siege = false
    local cone_minimum_distance
    local allow_out_of_range_cone = false
    for turret_index = 1, #(candidate.cover_turrets or {}) do
      local turret = candidate.cover_turrets[turret_index]
      if turret.valid and is_flamethrower_turret(turret) and ranged_range <= get_attack_range(turret) + 0.5 then
        force_cone_siege = true
        local turret_distance_to_target = math.sqrt(distance_sq(turret.position, candidate.position))
        cone_minimum_distance = math.max(
          cone_minimum_distance or 0,
          math.max(2, get_attack_range(turret) + CONE_STAGING_SAFETY_BUFFER - turret_distance_to_target)
        )
        allow_out_of_range_cone = true
      end
    end

    if safe_support_position and not force_cone_siege then
      support_position = safe_support_position
      support_mode = "safe-standoff"
    else
      cone_lane_positions = runtime_ext.build_support_cone_positions(
        group.surface,
        candidate.position,
        fallback_support_position or safe_support_position or candidate.outside_position,
        preferred_side,
        analysis.probe_unit_name,
        ranged_range,
        cone_minimum_distance,
        allow_out_of_range_cone
      )

      if cone_lane_positions and #cone_lane_positions > 0 then
        support_position = copy_position(cone_lane_positions[math.ceil(#cone_lane_positions / 2)])
        support_mode = "cone-siege"
        if force_cone_siege then
          support_rejection_reason = "flame-unsafe-standoff"
        elseif safe_support_position then
          support_rejection_reason = "prefer-cone-coverage"
        else
          support_rejection_reason = preferred_side and "no-safe-same-side-standoff" or "no-safe-standoff"
        end
      else
        support_rejection_reason = force_cone_siege and "no-cone-siege-position"
          or (preferred_side and "no-safe-same-side-standoff" or "no-safe-standoff")
      end
    end
  end

  if support_mode == "cone-siege" and support_position and #find_covering_turrets(group.surface, group.force, rally_position) > 0 then
    rally_position = copy_position(support_position)
  end

  return rally_position, support_position, ranged_members, ranged_range, candidate.outside_direction, support_rejection_reason, support_mode, cone_lane_positions
end

local function find_walkable_position_near(surface, origin, probe_unit_name, search_radius)
  if is_position_walkable(surface, origin, probe_unit_name) then
    return copy_position(origin)
  end

  for radius = 1, search_radius do
    for dx = -radius, radius do
      for dy = -radius, radius do
        if math.abs(dx) == radius or math.abs(dy) == radius then
          local candidate = {
            x = origin.x + dx,
            y = origin.y + dy
          }
          if is_position_walkable(surface, candidate, probe_unit_name) then
            return candidate
          end
        end
      end
    end
  end

  return copy_position(origin)
end

function runtime_ext.build_support_cone_positions(surface, target_position, anchor_position, preferred_side, probe_unit_name, ranged_range, minimum_base_distance, allow_out_of_range)
  if not (target_position and anchor_position and ranged_range and ranged_range > 1.5) then
    return {}
  end

  local direction_x, direction_y = normalized_direction(target_position, anchor_position)
  if preferred_side then
    local side = get_side_definition(preferred_side)
    if side then
      direction_x = side.dx
      direction_y = side.dy
    end
  end
  if direction_x == 0 and direction_y == 0 then
    direction_x = -1
  end

  local perpendicular_x = -direction_y
  local perpendicular_y = direction_x
  local anchor_distance = math.sqrt(distance_sq(target_position, anchor_position))
  local base_distance = math.max(2, minimum_base_distance or 0, anchor_distance)
  if not allow_out_of_range then
    base_distance = math.min(base_distance, ranged_range - 0.75)
  end

  local best_lane_positions = {}
  for distance_step = 0, (allow_out_of_range and 8 or 0) do
    local lane_positions = {}
    local seen = {}
    local lane_distance = base_distance + distance_step

    for lane_offset = -2, 2 do
      local candidate = {
        x = target_position.x + direction_x * lane_distance + perpendicular_x * lane_offset * RANGED_CONE_LANE_SPREAD,
        y = target_position.y + direction_y * lane_distance + perpendicular_y * lane_offset * RANGED_CONE_LANE_SPREAD
      }
      candidate = find_walkable_position_near(surface, candidate, probe_unit_name, 2)
      local lane_is_valid = allow_out_of_range or distance_sq(candidate, target_position) <= (ranged_range - 0.25) * (ranged_range - 0.25)
      if lane_is_valid and #find_covering_turrets(surface, game.forces.enemy, candidate) == 0 then
        local lane_key = position_key(candidate)
        if not seen[lane_key] then
          lane_positions[#lane_positions + 1] = candidate
          seen[lane_key] = true
        end
      end
    end

    if #lane_positions > #best_lane_positions then
      best_lane_positions = lane_positions
    end

    if #lane_positions >= 3 or (not allow_out_of_range and #lane_positions > 0) then
      return lane_positions
    end
  end

  return best_lane_positions
end

function runtime_ext.get_cone_lane_indices(split_count)
  if split_count <= 1 then
    return {3}
  end

  if split_count == 2 then
    return {2, 4}
  end

  return {1, 3, 5}
end

function runtime_ext.choose_support_cone_lane(record, surface, enemy_force)
  local lane_positions = record.lane_positions
  if not lane_positions or #lane_positions == 0 then
    return nil, nil, 0, nil
  end

  local current_index = math.min(record.lane_index or math.ceil(#lane_positions / 2), #lane_positions)
  local best_index = current_index
  local best_score
  local best_hazards

  for lane_index = math.max(1, current_index - 1), math.min(#lane_positions, current_index + 1) do
    local lane_position = lane_positions[lane_index]
    local fires = surface.find_entities_filtered({
      position = lane_position,
      radius = FLAME_HAZARD_RADIUS
    })
    local fire_hazards = {}
    local fire_score = 0
    for fire_index = 1, #fires do
      local entity = fires[fire_index]
      if entity.valid and entity.type == "fire" then
        fire_hazards[#fire_hazards + 1] = copy_position(entity.position)
        fire_score = fire_score + math.max(1, math.floor((FLAME_HAZARD_RADIUS * FLAME_HAZARD_RADIUS - distance_sq(lane_position, entity.position)) + 0.5))
      end
    end
    local cover_count = #find_covering_turrets(surface, enemy_force, lane_position)
    local score = fire_score * 100 + cover_count * 10 + math.abs(lane_index - current_index)
    if not best_score or score < best_score then
      best_score = score
      best_index = lane_index
      best_hazards = fire_hazards
    end
  end

  return best_index, lane_positions, best_score or 0, best_hazards
end

local function get_site_entry_vector(site)
  local breach_center = average_positions(site.breach_positions) or site.target_position or {x = 0, y = 0}
  local direction_x, direction_y = 0, 0

  if site.approach_side then
    local side = get_side_definition(site.approach_side)
    if side then
      direction_x = -side.dx
      direction_y = -side.dy
    end
  end

  if direction_x == 0 and direction_y == 0 and site.rally_position then
    direction_x, direction_y = normalized_direction(site.rally_position, breach_center)
  end

  if direction_x == 0 and direction_y == 0 and site.support_position then
    direction_x, direction_y = normalized_direction(site.support_position, breach_center)
  end

  if direction_x == 0 and direction_y == 0 then
    direction_x = 1
  end

  return breach_center, direction_x, direction_y
end

function runtime_ext.get_breach_entry_progress(site, position)
  if not (site and position) then
    return nil, nil, nil
  end

  local breach_center, direction_x, direction_y = get_site_entry_vector(site)
  local perpendicular_x = -direction_y
  local perpendicular_y = direction_x
  local delta_x = position.x - breach_center.x
  local delta_y = position.y - breach_center.y
  local progress = delta_x * direction_x + delta_y * direction_y
  local lateral = math.abs(delta_x * perpendicular_x + delta_y * perpendicular_y)
  local lateral_limit = 2

  for index = 1, #(site.breach_positions or {}) do
    local breach_position = site.breach_positions[index]
    local breach_delta_x = breach_position.x - breach_center.x
    local breach_delta_y = breach_position.y - breach_center.y
    local breach_lateral = math.abs(breach_delta_x * perpendicular_x + breach_delta_y * perpendicular_y)
    if breach_lateral > lateral_limit then
      lateral_limit = breach_lateral
    end
  end

  return progress, lateral, lateral_limit + 2
end

local function update_site_entry_positions(site, surface)
  normalize_site(site)
  local breach_center, direction_x, direction_y = get_site_entry_vector(site)
  local probe_unit_name = site.probe_unit_name or UNIT_PROBE_FALLBACK
  local perpendicular_x = -direction_y
  local perpendicular_y = direction_x

  local entry_position = {
    x = breach_center.x + direction_x * BREACH_ENTRY_DISTANCE,
    y = breach_center.y + direction_y * BREACH_ENTRY_DISTANCE
  }
  local inside_rally_position = {
    x = breach_center.x + direction_x * INSIDE_RALLY_DISTANCE,
    y = breach_center.y + direction_y * INSIDE_RALLY_DISTANCE
  }
  local exploit_position = {
    x = breach_center.x + direction_x * BREACH_EXPLOIT_DISTANCE,
    y = breach_center.y + direction_y * BREACH_EXPLOIT_DISTANCE
  }

  if surface then
    entry_position = find_walkable_position_near(surface, entry_position, probe_unit_name, 3)
    inside_rally_position = find_walkable_position_near(surface, inside_rally_position, probe_unit_name, 4)
    exploit_position = find_walkable_position_near(surface, exploit_position, probe_unit_name, 5)
  end

  if site.seeded_inside_rally_position then
    inside_rally_position = copy_position(site.seeded_inside_rally_position)
  end

  if site.seeded_exploit_position then
    exploit_position = copy_position(site.seeded_exploit_position)
  end

  site.entry_position = entry_position
  site.inside_rally_position = inside_rally_position
  site.exploit_position = exploit_position
  site.flame_hazard_bounds = {
    left_top = {
      x = breach_center.x + direction_x * 1 - perpendicular_x * (FLAME_LANE_SPREAD + 2),
      y = breach_center.y + direction_y * 1 - perpendicular_y * (FLAME_LANE_SPREAD + 2)
    },
    right_bottom = {
      x = breach_center.x + direction_x * (BREACH_EXPLOIT_DISTANCE + 2) + perpendicular_x * (FLAME_LANE_SPREAD + 2),
      y = breach_center.y + direction_y * (BREACH_EXPLOIT_DISTANCE + 2) + perpendicular_y * (FLAME_LANE_SPREAD + 2)
    }
  }

  return breach_center, direction_x, direction_y
end

sample_line_positions = function(from_position, to_position, sample_count)
  local samples = {}
  local steps = math.max(1, sample_count)

  for step = 0, steps do
    local ratio = step / steps
    samples[#samples + 1] = {
      x = from_position.x + (to_position.x - from_position.x) * ratio,
      y = from_position.y + (to_position.y - from_position.y) * ratio
    }
  end

  return samples
end

local function turret_covers_breach_corridor(turret, site)
  if not site.entry_position then
    return false
  end

  local breach_center = average_positions(site.breach_positions) or site.target_position
  if not breach_center then
    return false
  end

  local corridor_end = {
    x = breach_center.x + (site.entry_position.x - breach_center.x) * (BREACH_CORRIDOR_DISTANCE / math.max(1, math.sqrt(distance_sq(breach_center, site.entry_position)))),
    y = breach_center.y + (site.entry_position.y - breach_center.y) * (BREACH_CORRIDOR_DISTANCE / math.max(1, math.sqrt(distance_sq(breach_center, site.entry_position))))
  }

  local samples = sample_line_positions(breach_center, corridor_end, 4)
  for index = 1, #samples do
    if position_covered_by_turret(turret, samples[index]) then
      return true
    end
  end

  return false
end

local function serialize_assault_targets(targets)
  local serialized = {}
  for index = 1, #targets do
    local target = targets[index]
    serialized[index] = {
      name = target.name,
      position = serialize_position(target.position),
      is_flame = target.is_flame,
      covers_corridor = target.covers_corridor,
      range = round_number(target.range, 2),
      distance_to_entry = round_number(math.sqrt(target.distance_sq), 2)
    }
  end
  return serialized
end

local function collect_local_assault_targets(surface, site)
  local enemy_force = game.forces.enemy
  update_site_entry_positions(site, surface)
  local search_position = site.entry_position or site.target_position
  local nearby_turrets = surface.find_entities_filtered({
    position = search_position,
    radius = LOCAL_ASSAULT_RADIUS,
    type = TURRET_FILTER,
    force = site.defense_force_name
  })

  local targets = {}
  local active_flame_turrets = {}

  for index = 1, #nearby_turrets do
    local turret = nearby_turrets[index]
    if is_combat_turret(turret, enemy_force) then
      local is_flame = is_flamethrower_turret(turret)
      local target = {
        key = position_key(turret.position),
        entity = turret,
        name = turret.name,
        position = copy_position(turret.position),
        is_flame = is_flame,
        range = get_attack_range(turret),
        covers_corridor = turret_covers_breach_corridor(turret, site),
        distance_sq = distance_sq(search_position, turret.position)
      }
      targets[#targets + 1] = target
      if is_flame then
        active_flame_turrets[#active_flame_turrets + 1] = serialize_position(turret.position)
      end
    end
  end

  table.sort(targets, function(left, right)
    if left.is_flame ~= right.is_flame then
      return left.is_flame
    end

    if left.covers_corridor ~= right.covers_corridor then
      return left.covers_corridor
    end

    if left.distance_sq ~= right.distance_sq then
      return left.distance_sq < right.distance_sq
    end

    return left.range > right.range
  end)

  site.assault_targets = serialize_assault_targets(targets)
  site.entry_clear = true
  for index = 1, #targets do
    if targets[index].covers_corridor then
      site.entry_clear = false
      break
    end
  end
  site.active_flame_turrets = active_flame_turrets

  return targets
end

local function site_has_open_entry(site, surface)
  normalize_site(site)
  update_site_entry_positions(site, surface)

  local open_enough = true
  if site.breach_positions and #site.breach_positions > 0 then
    open_enough = breach_open_enough(
      surface,
      site.defense_force_name,
      site.breach_positions,
      site.breach_required_segments
    )
  end

  if not open_enough then
    site.entry_open = false
    site.entry_clear = false
    site.assault_targets = {}
    site.active_flame_turrets = {}
    return false
  end

  if not site.entry_open then
    return false
  end

  collect_local_assault_targets(surface, site)
  return site.entry_clear == true
end

function runtime_ext.site_has_reusable_entry(site, surface)
  normalize_site(site)
  update_site_entry_positions(site, surface)

  local open_enough = true
  if site.breach_positions and #site.breach_positions > 0 then
    open_enough = breach_open_enough(
      surface,
      site.defense_force_name,
      site.breach_positions,
      site.breach_required_segments
    )
  end

  if not open_enough then
    site.entry_open = false
    return false
  end

  return site.entry_open and site.entry_position ~= nil
end

local function find_turret_entity(surface, defense_force_name, target_position, target_name)
  if not target_position then
    return nil
  end

  local turrets = surface.find_entities_filtered({
    position = target_position,
    radius = 1.5,
    type = TURRET_FILTER,
    force = defense_force_name
  })

  for index = 1, #turrets do
    local turret = turrets[index]
    if turret.valid and (not target_name or turret.name == target_name) then
      return turret
    end
  end

  return nil
end

local function get_site_active_assault_loads(site, exclude_record_id)
  local loads = {}
  local active_ids = {}

  for index = #site.assault_group_ids, 1, -1 do
    local record_id = site.assault_group_ids[index]
    local record = storage.group_ai[record_id]
    local group = record and get_group(record) or nil
    if record
      and group
      and record_id ~= exclude_record_id
      and record.state ~= "breach-exploiting"
      and record.state ~= "post-breach-planning" then
      local target_key = record.target_turret_position and position_key(record.target_turret_position) or nil
      if target_key then
        loads[target_key] = (loads[target_key] or 0) + count_group_members(group)
      end
      active_ids[#active_ids + 1] = record_id
    else
      table.remove(site.assault_group_ids, index)
    end
  end

  return loads, active_ids
end

local function choose_assault_target(site, surface, exclude_record_id)
  local targets = collect_local_assault_targets(surface, site)
  local loads = get_site_active_assault_loads(site, exclude_record_id)

  for index = 1, #targets do
    local target = targets[index]
    if (loads[target.key] or 0) < MAX_MELEE_PER_TURRET then
      return target, targets, loads
    end
  end

  return nil, targets, loads
end

local function build_flame_lane_positions(site, target, surface)
  update_site_entry_positions(site, surface)
  local entry_position = site.entry_position or site.target_position
  local direction_x, direction_y = normalized_direction(entry_position, target.position)
  local perpendicular_x = -direction_y
  local perpendicular_y = direction_x
  local base_staging_distance = target.range + CONE_STAGING_SAFETY_BUFFER + 3
  local probe_unit_name = site.probe_unit_name or UNIT_PROBE_FALLBACK
  local lane_positions = {}
  local offsets = {
    -FLAME_LANE_SPREAD,
    0,
    FLAME_LANE_SPREAD
  }

  for index = 1, #offsets do
    local offset = offsets[index]
    local chosen_position
    for distance_step = 0, 6 do
      local staging_distance = base_staging_distance + distance_step
      local anchor = {
        x = target.position.x - direction_x * staging_distance,
        y = target.position.y - direction_y * staging_distance
      }
      local lane_position = {
        x = anchor.x + perpendicular_x * offset,
        y = anchor.y + perpendicular_y * offset
      }
      lane_position = find_walkable_position_near(surface, lane_position, probe_unit_name, 2)
      if #find_covering_turrets(surface, game.forces.enemy, lane_position) == 0 then
        chosen_position = lane_position
        break
      end
      chosen_position = chosen_position or lane_position
    end
    lane_positions[index] = chosen_position
  end

  return lane_positions
end

local function get_fire_entities_near(surface, position)
  local fires = surface.find_entities_filtered({
    position = position,
    radius = FLAME_HAZARD_RADIUS
  })
  local hazards = {}
  local score = 0

  for index = 1, #fires do
    local entity = fires[index]
    if entity.valid and entity.type == "fire" then
      hazards[#hazards + 1] = copy_position(entity.position)
      score = score + math.max(1, math.floor((FLAME_HAZARD_RADIUS * FLAME_HAZARD_RADIUS - distance_sq(position, entity.position)) + 0.5))
    end
  end

  return score, hazards
end

local function choose_flame_lane(record, site, target, surface)
  local lane_positions = build_flame_lane_positions(site, target, surface)
  local current_lane = record.lane_index or 2
  local current_score
  local best_index = current_lane
  local best_score
  local best_hazards

  for index = 1, #lane_positions do
    local hazard_score, hazards = get_fire_entities_near(surface, lane_positions[index])
    local cover_count = #find_covering_turrets(surface, game.forces.enemy, lane_positions[index])
    hazard_score = hazard_score + cover_count * 1000
    if index == current_lane then
      current_score = hazard_score
    end
    if not best_score or hazard_score < best_score then
      best_index = index
      best_score = hazard_score
      best_hazards = hazards
    end
  end

  if current_score and current_score <= best_score then
    best_index = current_lane
    best_score = current_score
    local _, hazards = get_fire_entities_near(surface, lane_positions[best_index])
    best_hazards = hazards
  elseif math.abs(best_index - current_lane) > 1 then
    local preferred_index = (best_index > current_lane) and (current_lane + 1) or (current_lane - 1)
    local preferred_score, preferred_hazards = get_fire_entities_near(surface, lane_positions[preferred_index])
    if preferred_score <= best_score + 1 then
      best_index = preferred_index
      best_score = preferred_score
      best_hazards = preferred_hazards
    end
  end

  return best_index, lane_positions, best_score or 0, best_hazards or {}
end

local function begin_command(record, kind, target_position, radius, timeout)
  record.activated_tick = record.activated_tick or game.tick
  record.command_kind = kind
  record.command_distraction = record.pending_command_distraction or defines.distraction.none
  record.command_status = "active"
  record.command_result = defines.behavior_result.in_progress
  record.command_target_position = target_position and copy_position(target_position) or nil
  record.command_radius = radius or 3
  record.command_issued_tick = game.tick
  record.command_timeout = timeout
  record.command_completed_tick = nil
end

clear_command = function(record)
  record.command_kind = nil
  record.command_distraction = nil
  record.command_status = nil
  record.command_result = nil
  record.command_target_position = nil
  record.command_radius = nil
  record.command_issued_tick = nil
  record.command_timeout = nil
  record.command_completed_tick = nil
end

local function get_script_attack_distraction(_record)
  return defines.distraction.none
end

local function mark_command_complete(record, result, tick)
  if record.command_status == "active" then
    record.command_status = "completed"
    record.command_result = result
    record.command_completed_tick = tick
  end
end

local function command_finished(record, group)
  if record.command_status == "completed" then
    return true
  end

  if record.command_status ~= "active" then
    return false
  end

  if record.command_kind == "move" and record.command_target_position then
    local completion_radius = record.command_radius or 3
    if distance_sq(group.position, record.command_target_position) <= completion_radius * completion_radius then
      mark_command_complete(record, defines.behavior_result.success, game.tick)
      return true
    end
  end

  if record.command_kind == "move"
    and group.is_unit_group
    and group.state == defines.group_state.gathering
    and record.command_target_position
    and distance_sq(group.position, record.command_target_position) > (record.command_radius or 3) * (record.command_radius or 3) then
    if game.tick - record.command_issued_tick >= PROCESS_INTERVAL then
      group.start_moving()
    end
    return false
  end

  if not group.has_command and game.tick - record.command_issued_tick >= PROCESS_INTERVAL then
    local assumed_result = defines.behavior_result.success
    if record.command_kind == "move" and record.command_target_position then
      local completion_radius = record.command_radius or 3
      if distance_sq(group.position, record.command_target_position) > completion_radius * completion_radius then
        assumed_result = defines.behavior_result.fail
      end
    end

    mark_command_complete(record, assumed_result, game.tick)
    return true
  end

  if record.command_timeout and game.tick - record.command_issued_tick >= record.command_timeout then
    mark_command_complete(record, defines.behavior_result.fail, game.tick)
    return true
  end

  return false
end

local function set_group_autonomous(group)
  if group.valid and group.is_unit_group and group.is_script_driven then
    group.set_autonomous()
  end
end

local function remove_group_record(record_id, make_autonomous, reason)
  local record = storage.group_ai[record_id]
  if not record then
    return
  end

  record.surface_name = record.surface_name or (record.group and record.group.valid and record.group.surface.name or nil)
  record.last_position = record.last_position or (record.group and record.group.valid and copy_position(record.group.position) or nil)

  local group = get_group(record)
  if group and make_autonomous then
    set_group_autonomous(group)
  end

  local site = get_site_for_record(record)
  if site then
    remove_id_from_list(site.assault_group_ids, record.id)
    remove_id_from_list(site.cone_group_ids, record.id)
    remove_id_from_list(site.reserve_group_ids, record.id)
  end

  record_debug_event("group_cleanup", record, {reason = reason})
  storage.group_ai[record_id] = nil
end

local function register_group(group, role, parent_id, scenario)
  ensure_globals()

  if not (group and group.valid and group.force.valid and is_enemy_force(group.force)) then
    return nil
  end

  local record_id = group.unique_id
  local record = storage.group_ai[record_id]

  if not record then
    record = {
      id = record_id,
      role = role or "main",
      parent_id = parent_id,
      state = "tracking",
      replans = 0,
      support_spawned = false,
      debug_registered = false
    }
    storage.group_ai[record_id] = record
    table.insert(storage.group_queue, record_id)
  end

  normalize_group_record(record)
  record.group = group
  if role then
    if role == "support" or record.role ~= "support" then
      record.role = role
    end
  end
  record.parent_id = parent_id or record.parent_id
  record.scenario = scenario or record.scenario
  if not record.scenario and group.surface.name == DEBUG_ARENA_SURFACE_NAME and storage.debug.arena then
    record.scenario = storage.debug.arena.scenario
  end
  record.surface_name = group.surface.name
  record.last_seen_tick = game.tick
  record.last_position = copy_position(group.position)

  if not record.debug_registered then
    record.debug_registered = true
    record_debug_event("group_registered", record, {
      reason = "register",
      scenario = record.scenario
    })
  end

  return record
end

local function prune_siege_sites()
  for site_key, site in pairs(storage.siege_sites) do
    if site.expires_tick <= game.tick then
      storage.siege_sites[site_key] = nil
    end
  end
end

local function make_site_key(surface_index, position)
  return string.format("%d:%d:%d", surface_index, math.floor(position.x + 0.5), math.floor(position.y + 0.5))
end

local function get_or_create_siege_site(group, candidate, analysis)
  local rally_position, support_position, _, _, approach_side, support_rejection_reason, support_mode, cone_lane_positions =
    find_staging_positions(group, candidate, analysis)
  local breach_plan = build_breach_plan(analysis, candidate)
  local site_key = make_site_key(group.surface.index, candidate.position)
  local site = storage.siege_sites[site_key]

  if not site then
    site = {
      key = site_key,
      surface_index = group.surface.index,
      defense_force_name = candidate.entity.force.name,
      target_position = copy_position(candidate.position),
      approach_side = approach_side,
      rally_position = copy_position(rally_position),
      support_position = support_position and copy_position(support_position) or nil,
      support_mode = support_mode or "none",
      support_rejection_reason = support_rejection_reason,
      cone_lane_positions = copy_positions(cone_lane_positions),
      breach_positions = copy_positions(breach_plan.positions),
      breach_attack_order = copy_positions(breach_plan.attack_order),
      breach_required_segments = breach_plan.required_segments,
      breach_axis = breach_plan.axis,
      probe_unit_name = analysis.probe_unit_name,
      entry_open = false,
      entry_clear = false,
      assault_targets = {},
      assault_group_ids = {},
      cone_group_ids = {},
      reserve_group_ids = {},
      last_breach_pressure_tick = nil,
      expires_tick = game.tick + SIEGE_SITE_TTL
    }
    storage.siege_sites[site_key] = site
  else
    site.target_position = copy_position(candidate.position)
    site.approach_side = approach_side
    site.rally_position = copy_position(rally_position)
    site.support_position = support_position and copy_position(support_position) or nil
    site.support_mode = support_mode or "none"
    site.support_rejection_reason = support_rejection_reason
    site.cone_lane_positions = copy_positions(cone_lane_positions)
    site.breach_positions = copy_positions(breach_plan.positions)
    site.breach_attack_order = copy_positions(breach_plan.attack_order)
    site.breach_required_segments = breach_plan.required_segments
    site.breach_axis = breach_plan.axis
    site.probe_unit_name = analysis.probe_unit_name or site.probe_unit_name
    site.expires_tick = game.tick + SIEGE_SITE_TTL
  end

  update_site_entry_positions(site, group.surface)

  return site
end

local function find_nearby_siege_site(group)
  local best_site
  local best_distance
  local best_entry_site
  local best_entry_distance
  local search_radius_sq = SIEGE_SITE_RADIUS * SIEGE_SITE_RADIUS

  for site_key, site in pairs(storage.siege_sites) do
    if site.expires_tick <= game.tick then
      storage.siege_sites[site_key] = nil
    elseif site.surface_index == group.surface.index then
      local site_distance = distance_sq(group.position, site.target_position)
      if site_distance <= search_radius_sq and (not best_distance or site_distance < best_distance) then
        best_site = site
        best_distance = site_distance
      end

      if site.entry_open and site.entry_position and runtime_ext.site_has_reusable_entry(site, group.surface) then
        local entry_distance = distance_sq(group.position, site.entry_position)
        if entry_distance <= search_radius_sq and (not best_entry_distance or entry_distance < best_entry_distance) then
          best_entry_site = site
          best_entry_distance = entry_distance
        end
      end
    end
  end

  return best_entry_site or best_site
end

local function find_attack_target(surface, position, defense_force_name)
  local direct_targets = surface.find_entities_filtered({
    position = position,
    radius = 2.5,
    type = WALL_FILTER,
    force = defense_force_name
  })

  if #direct_targets > 0 then
    return direct_targets[1]
  end

  local fallback_targets = surface.find_entities_filtered({
    position = position,
    radius = ATTACK_RADIUS,
    force = defense_force_name
  })

  for index = 1, #fallback_targets do
    local entity = fallback_targets[index]
    if entity.valid and entity.health then
      return entity
    end
  end

  return nil
end

local function issue_move(record, group, position, radius)
  record.pending_command_distraction = defines.distraction.none
  group.set_command({
    type = defines.command.go_to_location,
    destination = position,
    radius = radius or 3,
    distraction = defines.distraction.none
  })

  if group.is_unit_group then
    group.start_moving()
  end

  begin_command(record, "move", position, radius or 3, MOVE_COMMAND_TIMEOUT)
  record.pending_command_distraction = nil
end

local function issue_safe_move(record, group, position, radius, reason)
  if prebreach_safety_required(record) then
    local covering_turrets = find_covering_turrets(group.surface, group.force, position)
    if #covering_turrets > 0 then
      emit_coverage_violation(record, position, reason or "covered-destination", covering_turrets)
      return false
    end

    local path_covered, path_sources = path_has_turret_coverage(group.surface, group.force, group.position, position)
    if path_covered then
      emit_coverage_violation(record, position, reason or "covered-path", path_sources)
      return false
    end
  end

  issue_move(record, group, position, radius)
  return true
end

local function reassert_move_command(record, group, position, radius, reason, use_safe_move)
  if not (record and group and record.command_kind == "move" and record.command_status == "active" and record.command_target_position) then
    return false
  end

  local completion_radius = radius or record.command_radius or 3
  if distance_sq(group.position, record.command_target_position) <= completion_radius * completion_radius then
    return false
  end

  if game.tick - (record.command_issued_tick or game.tick) < MOVE_REASSERT_TICKS then
    return false
  end

  record_debug_event("command_reasserted", record, {
    reason = reason or "move-stuck",
    target_position = position or record.command_target_position,
    command_kind = record.command_kind,
    command_distraction = record.command_distraction,
    command_target_position = record.command_target_position,
    script_command_preserved = true
  })

  if group.is_unit_group and group.state == defines.group_state.gathering then
    group.start_moving()
    record.command_issued_tick = game.tick
    return true
  end

  clear_command(record)
  if use_safe_move then
    return issue_safe_move(record, group, position or record.command_target_position, completion_radius, reason)
  end

  issue_move(record, group, position or record.command_target_position, completion_radius)
  return true
end

local function issue_attack(record, group, target_position, defense_force_name)
  local target_entity = find_attack_target(group.surface, target_position, defense_force_name)
  local distraction = get_script_attack_distraction(record)

  if record.entry_open then
    local wall_target = target_entity
    if not (wall_target and wall_target.valid and (wall_target.type == "wall" or wall_target.type == "gate")) then
      wall_target = find_wall_entity_at(group.surface, defense_force_name, target_position)
    end
    if wall_target and wall_target.valid and (wall_target.type == "wall" or wall_target.type == "gate") then
      record_debug_event("wall_target_after_breach", record, {
        reason = "post-breach-wall-target",
        target_position = wall_target.position,
        target_turret_name = wall_target.name,
        target_turret_position = wall_target.position,
        entry_open = true
      })
    end
  end

  if target_entity then
    group.set_command({
      type = defines.command.attack,
      target = target_entity,
      distraction = distraction
    })
  else
    group.set_command({
      type = defines.command.attack_area,
      destination = target_position,
      radius = ATTACK_RADIUS,
      distraction = distraction
    })
  end

  if group.is_unit_group then
    group.start_moving()
  end

  record.pending_command_distraction = distraction
  begin_command(record, "attack", target_position, ATTACK_RADIUS, ATTACK_COMMAND_TIMEOUT)
  record.pending_command_distraction = nil
end

local function issue_attack_entity(record, group, target_entity)
  if not (target_entity and target_entity.valid) then
    return false
  end

  record.target_position = copy_position(target_entity.position)
  record.target_turret_position = copy_position(target_entity.position)
  record.target_turret_name = target_entity.name
  local distraction = get_script_attack_distraction(record)

  if record.entry_open and (target_entity.type == "wall" or target_entity.type == "gate") then
    record_debug_event("wall_target_after_breach", record, {
      reason = "post-breach-wall-target",
      target_position = target_entity.position,
      target_turret_name = target_entity.name,
      target_turret_position = target_entity.position,
      entry_open = true
    })
  end

  group.set_command({
    type = defines.command.attack,
    target = target_entity,
    distraction = distraction
  })

  if group.is_unit_group then
    group.start_moving()
  end

  record.pending_command_distraction = distraction
  begin_command(record, "attack", target_entity.position, ATTACK_RADIUS, ATTACK_COMMAND_TIMEOUT)
  record.pending_command_distraction = nil
  return true
end

get_site_for_record = function(record)
  if not (record and record.siege_site_id) then
    return nil
  end

  return storage.siege_sites[record.siege_site_id]
end

function runtime_ext.find_interior_target(site, surface)
  local turret_targets = collect_local_assault_targets(surface, site)
  if #turret_targets > 0 then
    local first_target = turret_targets[1]
    if first_target.entity and first_target.entity.valid then
      return first_target.entity
    end

    local fallback_turrets = surface.find_entities_filtered({
      position = first_target.position,
      radius = 1.5,
      type = TURRET_FILTER,
      force = site.defense_force_name
    })
    for turret_index = 1, #fallback_turrets do
      local turret = fallback_turrets[turret_index]
      if turret.valid and turret.name == first_target.name then
        return turret
      end
    end
  end

  local search_position = site.exploit_position or site.inside_rally_position or site.entry_position or site.target_position
  if not search_position then
    return nil
  end

  local enemy_force = game.forces.enemy
  local entities = surface.find_entities_filtered({
    position = search_position,
    radius = LOCAL_ASSAULT_RADIUS,
    force = site.defense_force_name
  })
  local best_entity
  local best_priority
  local best_distance

  for index = 1, #entities do
    local entity = entities[index]
    if entity.valid and entity.health and entity.type ~= "wall" and entity.type ~= "gate" then
      local priority = is_combat_turret(entity, enemy_force) and 0 or 1
      local entity_distance = distance_sq(search_position, entity.position)
      if not best_entity
        or priority < best_priority
        or (priority == best_priority and entity_distance < best_distance) then
        best_entity = entity
        best_priority = priority
        best_distance = entity_distance
      end
    end
  end

  return best_entity
end

local function issue_breach_exploit(record, group, site, reason)
  update_site_entry_positions(site, group.surface)
  record.entry_open = site.entry_open
  record.site_entry_position = copy_position(site.entry_position)
  record.inside_rally_position = copy_position(site.inside_rally_position)
  record.exploit_position = copy_position(site.exploit_position)
  record.target_position = copy_position(site.exploit_position or site.inside_rally_position or site.entry_position or site.target_position)
  record.target_force_name = site.defense_force_name
  record.state = "breach-exploiting"

  if ensure_entry_traversed(record, group, site) then
    return
  end

  local interior_target = runtime_ext.find_interior_target(site, group.surface)
  if interior_target then
    record.target_position = copy_position(interior_target.position)
    record_debug_event("interior_target_selected", record, {
      reason = is_combat_turret(interior_target, game.forces.enemy) and "combat-turret" or "interior-structure",
      target_turret_name = interior_target.name,
      target_turret_position = interior_target.position,
      target_position = interior_target.position,
      siege_site_id = site.key,
      entry_open = site.entry_open
    })
    record_debug_event("attack_selected", record, {
      reason = reason or "breach-exploit",
      target_position = interior_target.position,
      siege_site_id = site.key,
      target_turret_name = interior_target.name,
      target_turret_position = interior_target.position,
      entry_open = site.entry_open
    })
    issue_attack_entity(record, group, interior_target)
    return
  end

  group.set_command({
    type = defines.command.attack_area,
    destination = record.target_position,
    radius = ATTACK_RADIUS,
    distraction = defines.distraction.by_enemy
  })

  if group.is_unit_group then
    group.start_moving()
  end

  begin_command(record, "attack", record.target_position, ATTACK_RADIUS, ATTACK_COMMAND_TIMEOUT)
  record_debug_event("attack_selected", record, {
    reason = reason or "breach-exploit",
    target_position = record.target_position,
    siege_site_id = site.key,
    entry_open = site.entry_open
  })
end

local function update_breach_progress(record, surface)
  if not record.breach_positions then
    record.breach_open_segments = nil
    return false, 0
  end

  local open_enough, open_segments = breach_open_enough(
    surface,
    record.target_force_name,
    record.breach_positions,
    record.breach_required_segments
  )

  if record.breach_open_segments ~= open_segments then
    note_meaningful_progress(record)
    record_debug_event("breach_progress_updated", record, {
      reason = open_segments > (record.breach_open_segments or 0) and "segment-opened" or "segment-regressed",
      breach_open_segments = open_segments,
      breach_required_segments = record.breach_required_segments
    })
  end

  record.breach_open_segments = open_segments
  return open_enough, open_segments
end

local function allocate_members(member_pool, count)
  local allocated = {}

  while #allocated < count and #member_pool > 0 do
    allocated[#allocated + 1] = table.remove(member_pool)
  end

  return allocated
end

local function create_split_group(surface, force, position, members)
  local split_group = surface.create_unit_group({
    position = position,
    force = force
  })
  local moved_members = 0

  for index = 1, #members do
    local member = members[index]
    if member.valid then
      split_group.add_member(member)
      moved_members = moved_members + 1
    end
  end

  if moved_members == 0 then
    split_group.destroy()
    return nil
  end

  return split_group, moved_members
end

local function get_flame_lane_indices(split_count)
  if split_count <= 1 then
    return {2}
  end

  if split_count == 2 then
    return {1, 3}
  end

  return {1, 2, 3}
end

local function refresh_site_group_lists(site)
  for index = #site.assault_group_ids, 1, -1 do
    local record_id = site.assault_group_ids[index]
    local record = storage.group_ai[record_id]
    if not (record and get_group(record) and record.role == "assault") then
      table.remove(site.assault_group_ids, index)
    end
  end

  for index = #site.reserve_group_ids, 1, -1 do
    local record_id = site.reserve_group_ids[index]
    local record = storage.group_ai[record_id]
    if not (record and get_group(record)) then
      table.remove(site.reserve_group_ids, index)
    end
  end

  for index = #site.cone_group_ids, 1, -1 do
    local record_id = site.cone_group_ids[index]
    local record = storage.group_ai[record_id]
    if not (record and get_group(record) and record.role == "support") then
      table.remove(site.cone_group_ids, index)
    end
  end
end

local function assign_assault_record(assault_record, group, site, target, lane_index, lane_positions, assigned_melee_count)
  assault_record.role = "assault"
  assault_record.state = target.is_flame and "assault-staging" or "assault-engaging"
  assault_record.target_position = copy_position(target.position)
  assault_record.target_force_name = site.defense_force_name
  assault_record.target_turret_name = target.name
  assault_record.target_turret_position = copy_position(target.position)
  assault_record.siege_site_id = site.key
  assault_record.entry_open = true
  assault_record.site_entry_position = copy_position(site.entry_position)
  assault_record.inside_rally_position = copy_position(site.inside_rally_position)
  assault_record.exploit_position = copy_position(site.exploit_position)
  assault_record.lane_index = lane_index
  assault_record.lane_positions = copy_positions(lane_positions)
  assault_record.hazard_positions = nil
  append_unique_id(site.assault_group_ids, assault_record.id)

  record_debug_event("melee_split_created", assault_record, {
    reason = target.is_flame and "flame-assault" or "turret-assault",
    target_turret_name = target.name,
    target_turret_position = target.position,
    assigned_melee_count = assigned_melee_count,
    entry_open = true,
    lane_index = lane_index
  })

  if target.is_flame and lane_index and lane_positions and lane_positions[lane_index] then
    record_debug_event("flame_lane_set", assault_record, {
      reason = "initial-lane",
      target_position = lane_positions[lane_index],
      target_turret_name = target.name,
      target_turret_position = target.position,
      lane_index = lane_index,
      entry_open = true
    })
    issue_move(assault_record, group, lane_positions[lane_index], 2)
  else
    local target_entity = target.entity or find_turret_entity(group.surface, site.defense_force_name, target.position, target.name)
    if target_entity then
      issue_attack_entity(assault_record, group, target_entity)
    end
  end
end

local function spawn_assault_groups_from_reserve(record, group, site, targets)
  refresh_site_group_lists(site)
  local melee_members = get_group_melee_members(group)
  if #melee_members == 0 then
    return 0
  end

  local loads = get_site_active_assault_loads(site)
  local created = 0

  for target_index = 1, #targets do
    local target = targets[target_index]
    local available_capacity = MAX_MELEE_PER_TURRET - (loads[target.key] or 0)
    if available_capacity > 0 and #melee_members > 0 then
      local total_assigned = math.min(available_capacity, #melee_members)
      local split_count = 1
      local lane_positions
      local lane_indices = {2}

      if target.is_flame then
        split_count = math.min(FLAME_LANE_COUNT, math.max(1, math.ceil(total_assigned / 4)))
        lane_positions = build_flame_lane_positions(site, target, group.surface)
        lane_indices = get_flame_lane_indices(split_count)
      end

      record_debug_event("turret_priority_selected", record, {
        reason = target.is_flame and "flame-first" or "turret-priority",
        target_turret_name = target.name,
        target_turret_position = target.position,
        assigned_melee_count = total_assigned,
        entry_open = true
      })

      local assigned_remaining = total_assigned
      for split_index = 1, split_count do
        if assigned_remaining <= 0 or #melee_members == 0 then
          break
        end

        local remaining_groups = split_count - split_index + 1
        local member_count = math.min(#melee_members, math.ceil(assigned_remaining / remaining_groups))
        local allocated_members = allocate_members(melee_members, member_count)
        local split_group, moved_members = create_split_group(group.surface, group.force, group.position, allocated_members)
        moved_members = moved_members or 0

        if split_group and moved_members > 0 then
          local assault_record = register_group(split_group, "assault", record.id, record.scenario)
          if assault_record then
            assign_assault_record(
              assault_record,
              split_group,
              site,
              target,
              lane_indices[split_index] or 2,
              lane_positions,
              moved_members
            )
            created = created + 1
          end
        end

        assigned_remaining = assigned_remaining - moved_members
      end

      loads[target.key] = (loads[target.key] or 0) + total_assigned
    end

    if #melee_members == 0 then
      break
    end
  end

  return created
end

local function mark_reserve_record(record, group, site)
  refresh_site_group_lists(site)
  record.role = "reserve"
  record.state = "post-breach-planning"
  record.entry_open = true
  record.site_entry_position = copy_position(site.entry_position)
  record.inside_rally_position = copy_position(site.inside_rally_position)
  record.exploit_position = copy_position(site.exploit_position)
  remove_id_from_list(site.assault_group_ids, record.id)
  append_unique_id(site.reserve_group_ids, record.id)

  if not record.reserve_registered then
    record.reserve_registered = true
    record_debug_event("reserve_group_created", record, {
      reason = "reserve",
      assigned_melee_count = count_group_members(group),
      entry_open = true
    })
  end

  local hold_position = site.inside_rally_position
  local melee_members = get_group_melee_members(group)
  local _, ranged_range = get_group_ranged_members(group)
  if #melee_members == 0 and ranged_range > 1.5 then
    if site.active_flame_turrets and #site.active_flame_turrets > 0 then
      hold_position = site.support_position or site.rally_position or site.entry_position
    elseif site.support_position then
      hold_position = site.support_position
    end
  end

  if hold_position and distance_sq(group.position, hold_position) > 16 then
    issue_move(record, group, hold_position, 3)
  end
end

local function start_post_breach_planning(record, group, reason)
  local site = get_site_for_record(record)
  if not site then
    return false
  end

  normalize_site(site)
  site.entry_open = true
  site.expires_tick = game.tick + SIEGE_SITE_TTL
  update_site_entry_positions(site, group.surface)
  clear_command(record)
  record.entry_open = true
  record.site_entry_position = copy_position(site.entry_position)
  record.inside_rally_position = copy_position(site.inside_rally_position)
  record.exploit_position = copy_position(site.exploit_position)
  record.state = "post-breach-planning"

  record_debug_event("breach_assault_planned", record, {
    reason = reason or "breach-open",
    target_position = site.entry_position,
    siege_site_id = site.key,
    entry_open = true,
    breach_required_segments = record.breach_required_segments,
    breach_open_segments = record.breach_open_segments
  })

  return true
end

ensure_entry_traversed = function(record, group, site)
  if not (site and site.entry_open) then
    return false
  end

  update_site_entry_positions(site, group.surface)
  local breach_center, direction_x, direction_y = get_site_entry_vector(site)
  local destination = site.inside_rally_position or site.entry_position or breach_center
  if not destination then
    return false
  end

  local outside_approach = {
    x = breach_center.x - direction_x * BREACH_ENTRY_DISTANCE,
    y = breach_center.y - direction_y * BREACH_ENTRY_DISTANCE
  }
  outside_approach = find_walkable_position_near(group.surface, outside_approach, get_group_probe_unit_name(group), 3)

  record.entry_open = true
  record.site_entry_position = copy_position(site.entry_position)
  record.inside_rally_position = copy_position(site.inside_rally_position)
  record.exploit_position = copy_position(site.exploit_position)

  local progress, lateral, lateral_limit = runtime_ext.get_breach_entry_progress(site, group.position)
  record.entry_progress = progress
  local stage = "approach"
  local move_destination = outside_approach

  if progress and lateral and lateral_limit then
    if lateral > lateral_limit or progress < -0.5 then
      stage = "approach"
      move_destination = outside_approach
    elseif progress < 0.5 then
      stage = "breach-center"
      move_destination = breach_center
    elseif progress < (BREACH_ENTRY_DISTANCE - 0.5) and site.entry_position then
      stage = "entry"
      move_destination = site.entry_position
    else
      stage = "inside"
      move_destination = destination
    end
  end

  if record.entry_progress_stage ~= stage then
    record.entry_progress_stage = stage
    record_debug_event("entry_progress_updated", record, {
      reason = stage,
      target_position = move_destination,
      entry_progress = progress,
      entry_open = true
    })
    note_meaningful_progress(record, group.position)
  end

  if stage == "inside" and distance_sq(group.position, destination) <= POST_BREACH_ENTRY_RADIUS * POST_BREACH_ENTRY_RADIUS then
    return false
  end

  if command_finished(record, group) then
    clear_command(record)
  end

  if not record.command_status
    or record.command_kind ~= "move"
    or not record.command_target_position
    or distance_sq(record.command_target_position, move_destination) > 1 then
    issue_move(record, group, move_destination, POST_BREACH_ENTRY_RADIUS)
  end

  return true
end

local function assign_next_assault_target(record, group, site)
  local target, targets = choose_assault_target(site, group.surface, record.id)
  if not target then
    if targets and #targets > 0 then
      record.role = "reserve"
      remove_id_from_list(site.assault_group_ids, record.id)
      append_unique_id(site.reserve_group_ids, record.id)
      record.state = "post-breach-planning"
      if site.inside_rally_position then
        issue_move(record, group, site.inside_rally_position, 3)
      end
    else
      issue_breach_exploit(record, group, site, "assault-exploit")
    end
    return false
  end

  record.target_turret_name = target.name
  record.target_turret_position = copy_position(target.position)
  record.target_force_name = site.defense_force_name
  record.target_position = copy_position(target.position)
  record.entry_open = true
  record.site_entry_position = copy_position(site.entry_position)
  record.inside_rally_position = copy_position(site.inside_rally_position)
  record.exploit_position = copy_position(site.exploit_position)

  record_debug_event("turret_priority_selected", record, {
    reason = target.is_flame and "retarget-flame" or "retarget",
    target_turret_name = target.name,
    target_turret_position = target.position,
    assigned_melee_count = count_group_members(group),
    entry_open = true
  })

  if target.is_flame then
    local lane_index, lane_positions = choose_flame_lane(record, site, target, group.surface)
    record.lane_index = lane_index
    record.lane_positions = copy_positions(lane_positions)
    record.state = "assault-staging"
    record_debug_event("flame_lane_set", record, {
      reason = "retarget-lane",
      target_position = lane_positions[lane_index],
      target_turret_name = target.name,
      target_turret_position = target.position,
      lane_index = lane_index,
      entry_open = true
    })
    issue_move(record, group, lane_positions[lane_index], 2)
    return true
  end

  record.state = "assault-engaging"
  local target_entity = target.entity or find_turret_entity(group.surface, site.defense_force_name, target.position, target.name)
  if target_entity then
    issue_attack_entity(record, group, target_entity)
  end
  return true
end

local function issue_support_breach_attack(record, group)
  local target_entity, target_position = find_next_breach_target(
    group.surface,
    record.target_force_name,
    record.breach_positions,
    record.breach_attack_order
  )

  if not target_entity then
    return false
  end

  record.target_position = copy_position(target_position)

  if record.support_mode == "cone-siege" and record.lane_positions and #record.lane_positions > 0 then
    local lane_index, lane_positions, hazard_score, hazards = runtime_ext.choose_support_cone_lane(record, group.surface, group.force)
    if not lane_index or not lane_positions or not lane_positions[lane_index] then
      return false
    end

    local lane_changed = lane_index ~= record.lane_index
    record.lane_index = lane_index
    record.hazard_positions = hazards

    if lane_changed then
      record_debug_event("ranged_cone_lane_set", record, {
        reason = "lane-shift",
        target_position = lane_positions[lane_index],
        lane_index = lane_index,
        hazard_score = hazard_score,
        support_mode = "cone-siege"
      })
      if hazard_score > 0 then
        record_debug_event("fire_hazard_avoided", record, {
          reason = "cone-lane-shift",
          target_position = lane_positions[lane_index],
          lane_index = lane_index,
          hazard_score = hazard_score,
          support_mode = "cone-siege"
        })
      end
    end

    if distance_sq(group.position, lane_positions[lane_index]) > SUPPORT_RETURN_RADIUS * SUPPORT_RETURN_RADIUS then
      issue_safe_move(record, group, lane_positions[lane_index], SUPPORT_RETURN_RADIUS, "cone-lane-covered")
      return true
    end
  elseif record.support_position and distance_sq(group.position, record.support_position) > SUPPORT_RETURN_RADIUS * SUPPORT_RETURN_RADIUS then
    issue_safe_move(record, group, record.support_position, SUPPORT_RETURN_RADIUS, "support-position-covered")
    return true
  end

  note_meaningful_progress(record, group.position)
  return issue_attack_entity(record, group, target_entity)
end

start_fallback_attack = function(record, group, reason)
  local target_position = record.target_position
  local defense_force_name = record.target_force_name

  if not (target_position and defense_force_name) then
    set_group_autonomous(group)
    remove_group_record(record.id, false, "missing-fallback-target")
    return
  end

  issue_attack(record, group, target_position, defense_force_name)
  record.state = "fallback-attack"
  record.fallback_deadline_tick = game.tick + FALLBACK_ATTACK_TICKS

  record_debug_event("fallback_issued", record, {
    reason = reason or "fallback",
    target_position = target_position
  })
end

function runtime_ext.release_child_support_groups(parent_id, reason)
  local released_ids = {}
  for record_id, child_record in pairs(storage.group_ai) do
    if child_record.parent_id == parent_id and child_record.role == "support" then
      released_ids[#released_ids + 1] = record_id
    end
  end

  for index = 1, #released_ids do
    local child_record = storage.group_ai[released_ids[index]]
    local child_group = child_record and get_group(child_record) or nil
    if child_group then
      set_group_autonomous(child_group)
    end
    if child_record then
      remove_group_record(released_ids[index], false, reason or "support-release")
    end
  end
end

local function attach_support_group(record, site, ranged_members)
  if record.support_spawned or not site.support_position or #ranged_members == 0 then
    return
  end

  record.support_spawned = true

  local support_group = record.group.surface.create_unit_group({
    position = site.support_position or record.group.position,
    force = record.group.force
  })

  local moved_members = 0
  for index = 1, #ranged_members do
    local member = ranged_members[index]
    if member.valid then
      support_group.add_member(member)
      moved_members = moved_members + 1
    end
  end

  if moved_members == 0 then
    support_group.destroy()
    return
  end

  local support_record = register_group(support_group, "support", record.id, record.scenario)
  if support_record then
    support_record.state = "support-moving"
    support_record.target_position = copy_position(site.target_position)
    support_record.target_force_name = site.defense_force_name
    support_record.support_position = copy_position(site.support_position)
    support_record.support_mode = "safe-standoff"
    support_record.breach_positions = copy_positions(site.breach_positions)
    support_record.breach_attack_order = copy_positions(site.breach_attack_order)
    support_record.breach_required_segments = site.breach_required_segments
    support_record.breach_open_segments = 0
    support_record.siege_site_id = site.key
    record.support_group_id = support_record.id
    record.support_group_ids = {support_record.id}

    record_debug_event("support_group_created", record, {
      reason = "support-group",
      support_group_id = support_record.id,
      target_position = site.target_position,
      siege_site_id = site.key
    })
  end
end

function runtime_ext.attach_cone_support_groups(record, site, ranged_members)
  if record.support_spawned or #ranged_members == 0 then
    return
  end

  local lane_positions = site.cone_lane_positions or {}
  if #lane_positions == 0 then
    return
  end

  record.support_spawned = true
  record.support_group_ids = {}
  site.cone_group_ids = site.cone_group_ids or {}
  local split_count = math.min(RANGED_CONE_GROUP_LIMIT, #ranged_members, #lane_positions)
  local lane_indices = runtime_ext.get_cone_lane_indices(split_count)

  for split_index = 1, split_count do
    local remaining_groups = split_count - split_index + 1
    local member_count = math.ceil(#ranged_members / remaining_groups)
    local allocated_members = allocate_members(ranged_members, member_count)
    local lane_index = math.min(lane_indices[split_index] or math.ceil(#lane_positions / 2), #lane_positions)
    local split_group, moved_members = create_split_group(
      record.group.surface,
      record.group.force,
      lane_positions[lane_index] or record.group.position,
      allocated_members
    )
    moved_members = moved_members or 0

    if split_group and moved_members > 0 then
      local support_record = register_group(split_group, "support", record.id, record.scenario)
      if support_record then
        support_record.state = "support-moving"
        support_record.target_position = copy_position(site.target_position)
        support_record.target_force_name = site.defense_force_name
        support_record.support_position = copy_position(lane_positions[lane_index])
        support_record.support_mode = "cone-siege"
        support_record.lane_index = lane_index
        support_record.lane_positions = copy_positions(lane_positions)
        support_record.breach_positions = copy_positions(site.breach_positions)
        support_record.breach_attack_order = copy_positions(site.breach_attack_order)
        support_record.breach_required_segments = site.breach_required_segments
        support_record.breach_open_segments = 0
        support_record.siege_site_id = site.key
        record.support_group_ids[#record.support_group_ids + 1] = support_record.id
        record.support_group_id = record.support_group_id or support_record.id
        append_unique_id(site.cone_group_ids, support_record.id)

        record_debug_event("ranged_cone_group_created", support_record, {
          reason = "cone-group",
          support_group_id = support_record.id,
          assigned_melee_count = moved_members,
          target_position = lane_positions[lane_index],
          siege_site_id = site.key,
          support_mode = "cone-siege"
        })
        record_debug_event("ranged_cone_lane_set", support_record, {
          reason = "initial-lane",
          target_position = lane_positions[lane_index],
          lane_index = lane_index,
          siege_site_id = site.key,
          support_mode = "cone-siege"
        })
      end
    end
  end
end

local function begin_siege(record, group, site)
  normalize_site(site)
  update_site_entry_positions(site, group.surface)
  local reusable_entry = site.entry_open and runtime_ext.site_has_reusable_entry(site, group.surface)
  local same_site = record.siege_site_id == site.key
  record.target_position = copy_position(site.target_position)
  record.target_force_name = site.defense_force_name
  record.approach_side = site.approach_side
  record.rally_position = copy_position(site.rally_position)
  record.support_position = site.support_position and copy_position(site.support_position) or nil
  record.support_mode = site.support_mode or "none"
  record.support_rejection_reason = site.support_rejection_reason
  record.support_group_id = nil
  record.support_group_ids = {}
  record.support_spawned = false
  record.breach_positions = copy_positions(site.breach_positions)
  record.breach_attack_order = copy_positions(site.breach_attack_order)
  record.breach_required_segments = site.breach_required_segments
  record.breach_open_segments = 0
  record.breach_wait_started_tick = nil
  if not same_site then
    record.breach_replan_used = false
  end
  record.siege_site_id = site.key
  record.site_entry_position = copy_position(site.entry_position)
  record.inside_rally_position = copy_position(site.inside_rally_position)
  record.exploit_position = copy_position(site.exploit_position)
  record.entry_open = site.entry_open
  record.lane_positions = nil
  record.lane_index = nil
  runtime_ext.release_child_support_groups(record.id, "support-rebind")

  local ranged_members, ranged_range = get_group_ranged_members(group)
  record.waiting_for_breach = false
  record_debug_event("support_mode_selected", record, {
    reason = site.support_mode or "none",
    target_position = site.support_position or site.rally_position,
    siege_site_id = site.key,
    approach_side = site.approach_side,
    support_mode = site.support_mode or "none"
  })
  if ranged_range > 1.5 and site.support_mode == "safe-standoff" and site.support_position then
    record_debug_event("standoff_position_selected", record, {
      reason = "support-position",
      target_position = site.support_position,
      siege_site_id = site.key,
      approach_side = site.approach_side,
      support_mode = "safe-standoff"
    })
    attach_support_group(record, site, ranged_members)
    record.waiting_for_breach = record.support_group_id ~= nil and site.breach_required_segments and site.breach_required_segments > 1
  elseif ranged_range > 1.5 and site.support_mode == "cone-siege" and site.cone_lane_positions and #site.cone_lane_positions > 0 then
    runtime_ext.attach_cone_support_groups(record, site, ranged_members)
    record.waiting_for_breach = #(record.support_group_ids or {}) > 0 and site.breach_required_segments and site.breach_required_segments > 1
  elseif ranged_range > 1.5 then
    record_debug_event("support_position_rejected", record, {
      reason = site.support_rejection_reason or "support-position-rejected",
      target_position = site.rally_position,
      siege_site_id = site.key,
      approach_side = site.approach_side,
      support_rejection_reason = site.support_rejection_reason,
      support_mode = site.support_mode or "none"
    })
  end

  if record.waiting_for_breach then
    record.breach_wait_started_tick = game.tick
  end

  if count_group_members(group) == 0 then
    remove_group_record(record.id, false, "empty-after-support-split")
    return
  end

  if record.waiting_for_breach then
    local remaining_ranged_members, remaining_ranged_range = get_group_ranged_members(group)
    local current_cover = find_covering_turrets(group.surface, group.force, group.position)
    if #remaining_ranged_members == 0
      and remaining_ranged_range <= 1.5
      and #current_cover == 0 then
      record.rally_position = copy_position(group.position)
      site.rally_position = copy_position(group.position)
    end
  end

  if reusable_entry and site.inside_rally_position then
    local reuse_event_name = ((site.wave_count or 0) > 1) and "breach_reused" or "open_entry_taken"
    record_debug_event("siege_site_selected", record, {
      reason = "reuse-open-breach",
      target_position = site.entry_position,
      siege_site_id = site.key,
      entry_open = true
    })
    record_debug_event(reuse_event_name, record, {
      reason = "entry-open",
      target_position = site.entry_position,
      siege_site_id = site.key,
      entry_open = true
    })
    if #collect_local_assault_targets(group.surface, site) > 0 then
      clear_command(record)
      record.entry_open = true
      record.site_entry_position = copy_position(site.entry_position)
      record.inside_rally_position = copy_position(site.inside_rally_position)
      record.exploit_position = copy_position(site.exploit_position)
      record.state = "post-breach-planning"
      record_debug_event("breach_assault_planned", record, {
        reason = reuse_event_name,
        target_position = site.entry_position,
        siege_site_id = site.key,
        entry_open = true,
        breach_required_segments = record.breach_required_segments,
        breach_open_segments = record.breach_open_segments
      })
    else
      issue_breach_exploit(record, group, site, reuse_event_name)
    end
    return
  end

  record.state = "rallying"
  record_debug_event("siege_site_selected", record, {
    reason = "begin-siege",
    target_position = site.target_position,
    siege_site_id = site.key
  })
  record_debug_event("attack_selected", record, {
    reason = record.waiting_for_breach and "hold-for-breach" or "siege-rally",
    target_position = site.target_position,
    siege_site_id = site.key,
    breach_required_segments = record.breach_required_segments,
    breach_open_segments = record.breach_open_segments
  })
  issue_safe_move(record, group, record.rally_position, 3, "siege-rally-covered")
end

function apply_site_to_record(record, site)
  normalize_site(site)
  record.siege_site_id = site.key
  record.approach_side = site.approach_side
  record.support_mode = site.support_mode or "none"
  record.breach_positions = copy_positions(site.breach_positions)
  record.breach_attack_order = copy_positions(site.breach_attack_order)
  record.breach_required_segments = site.breach_required_segments
  record.breach_open_segments = 0
  record.site_entry_position = copy_position(site.entry_position)
  record.inside_rally_position = copy_position(site.inside_rally_position)
  record.exploit_position = copy_position(site.exploit_position)
  record.entry_open = site.entry_open
end

function find_support_follow_target(site, surface)
  if site.active_flame_turrets and #site.active_flame_turrets > 0 then
    return nil, nil
  end

  refresh_site_group_lists(site)
  for index = 1, #site.assault_group_ids do
    local assault_record = storage.group_ai[site.assault_group_ids[index]]
    local assault_group = assault_record and get_group(assault_record) or nil
    if assault_record
      and assault_group
      and (assault_record.state == "assault-engaging" or assault_record.state == "assault-staging")
      and assault_record.target_turret_position
      and assault_record.target_turret_name ~= "flamethrower-turret" then
      local turret = find_turret_entity(surface, site.defense_force_name, assault_record.target_turret_position, assault_record.target_turret_name)
      if turret and distance_sq(assault_group.position, turret.position) <= SUPPORT_FOLLOW_TRIGGER_DISTANCE * SUPPORT_FOLLOW_TRIGGER_DISTANCE then
        return turret, assault_record
      end
    end
  end

  return nil, nil
end

function find_support_follow_position(group, site, turret)
  local _, ranged_range = get_group_ranged_members(group)
  if ranged_range <= 1.5 then
    return nil
  end

  local entry_position = site.entry_position or site.target_position
  local direction_x, direction_y = normalized_direction(turret.position, entry_position)
  if direction_x == 0 and direction_y == 0 then
    direction_x = -1
  end
  local perpendicular_x = -direction_y
  local perpendicular_y = direction_x
  local distance_to_entry = math.sqrt(distance_sq(entry_position, turret.position))
  local follow_distance = math.max(
    SUPPORT_FOLLOW_MIN_DISTANCE,
    math.min(ranged_range - 0.5, math.max(SUPPORT_FOLLOW_DISTANCE, distance_to_entry - 1))
  )
  local probe_unit_name = get_group_probe_unit_name(group)
  local best_position
  local best_distance
  local lateral_offsets = {0, 1.5, -1.5}

  for index = 1, #lateral_offsets do
    local offset = lateral_offsets[index]
    local candidate = {
      x = turret.position.x + direction_x * follow_distance + perpendicular_x * offset,
      y = turret.position.y + direction_y * follow_distance + perpendicular_y * offset
    }
    candidate = find_walkable_position_near(group.surface, candidate, probe_unit_name, 2)
    local candidate_distance = distance_sq(group.position, candidate)
    if not best_distance or candidate_distance < best_distance then
      best_position = candidate
      best_distance = candidate_distance
    end
  end

  return best_position
end

function handle_post_breach_planning(record, group)
  local site = get_site_for_record(record)
  if not site then
    set_group_autonomous(group)
    remove_group_record(record.id, false, "missing-post-breach-site")
    return
  end

  normalize_site(site)
  site.entry_open = true
  site.expires_tick = game.tick + SIEGE_SITE_TTL
  local targets = collect_local_assault_targets(group.surface, site)

  if command_finished(record, group) then
    clear_command(record)
  end

  if #targets == 0 then
    issue_breach_exploit(record, group, site, "no-local-turrets")
    return
  end

  local focus_target = targets[1]
  if focus_target then
    record.target_position = copy_position(focus_target.position)
    record.target_turret_name = focus_target.name
    record.target_turret_position = copy_position(focus_target.position)
    record_debug_event("interior_target_selected", record, {
      reason = focus_target.is_flame and "flame-turret" or "combat-turret",
      target_turret_name = focus_target.name,
      target_turret_position = focus_target.position,
      target_position = focus_target.position,
      siege_site_id = site.key,
      entry_open = true
    })
  end

  if ensure_entry_traversed(record, group, site) then
    local stalled_entry = record.state_since_tick
      and game.tick - record.state_since_tick >= POST_BREACH_ASSAULT_HANDOFF_TICKS
    if stalled_entry and focus_target then
      clear_command(record)
      record.role = "assault"
      remove_id_from_list(site.reserve_group_ids, record.id)
      append_unique_id(site.assault_group_ids, record.id)
      assign_next_assault_target(record, group, site)
    end
    return
  end

  spawn_assault_groups_from_reserve(record, group, site, targets)

  if count_group_members(group) == 0 then
    remove_group_record(record.id, false, "all-melee-split")
    return
  end

  mark_reserve_record(record, group, site)
end

function handle_assault_state(record, group)
  local site = get_site_for_record(record)
  if not site then
    set_group_autonomous(group)
    remove_group_record(record.id, false, "missing-assault-site")
    return
  end

  normalize_site(site)
  local target_entity = find_turret_entity(group.surface, site.defense_force_name, record.target_turret_position, record.target_turret_name)
  if not target_entity then
    clear_command(record)
    assign_next_assault_target(record, group, site)
    return
  end

  if record.target_turret_name == "flamethrower-turret" then
    local target = {
      name = target_entity.name,
      position = copy_position(target_entity.position),
      is_flame = true,
      range = get_attack_range(target_entity)
    }
    local lane_index, lane_positions, hazard_score, hazards = choose_flame_lane(record, site, target, group.surface)
    local lane_changed = lane_index ~= record.lane_index
    record.lane_index = lane_index
    record.lane_positions = copy_positions(lane_positions)
    record.hazard_positions = hazards

    if lane_changed then
      record_debug_event("fire_hazard_avoided", record, {
        reason = "lane-shift",
        target_position = lane_positions[lane_index],
        target_turret_name = target.name,
        target_turret_position = target.position,
        lane_index = lane_index,
        hazard_score = hazard_score,
        entry_open = true
      })
    end

    if record.state == "assault-staging" then
      if command_finished(record, group)
        or distance_sq(group.position, lane_positions[lane_index]) <= 9 then
        clear_command(record)
        record.state = "assault-engaging"
        issue_attack_entity(record, group, target_entity)
      elseif lane_changed or not record.command_status then
        issue_move(record, group, lane_positions[lane_index], 2)
      end
      return
    end

    if hazard_score > 0 and distance_sq(group.position, target.position) > 16 then
      clear_command(record)
      record.state = "assault-staging"
      issue_move(record, group, lane_positions[lane_index], 2)
      return
    end
  end

  record.state = "assault-engaging"
  if command_finished(record, group) then
    clear_command(record)
    issue_attack_entity(record, group, target_entity)
  elseif not record.command_status then
    issue_attack_entity(record, group, target_entity)
  end
end

function handle_support_following(record, group)
  local site = get_site_for_record(record)
  if not site then
    set_group_autonomous(group)
    remove_group_record(record.id, false, "missing-support-site")
    return
  end

  normalize_site(site)
  site.entry_open = true
  site.expires_tick = game.tick + SIEGE_SITE_TTL
  local targets = collect_local_assault_targets(group.surface, site)
  if #targets == 0 then
    clear_command(record)
    set_group_autonomous(group)
    remove_group_record(record.id, false, "support-exploit-complete")
    return
  end

  if site.active_flame_turrets and #site.active_flame_turrets > 0 then
    if record.command_kind == "attack" then
      clear_command(record)
    end
    if record.support_position and distance_sq(group.position, record.support_position) > SUPPORT_RETURN_RADIUS * SUPPORT_RETURN_RADIUS then
      if command_finished(record, group) then
        clear_command(record)
      end
      if not record.command_status then
        issue_move(record, group, record.support_position, SUPPORT_RETURN_RADIUS)
      end
    end
    return
  end

  local turret, melee_record = find_support_follow_target(site, group.surface)
  if not turret then
    if record.support_position and distance_sq(group.position, record.support_position) > SUPPORT_RETURN_RADIUS * SUPPORT_RETURN_RADIUS then
      if command_finished(record, group) then
        clear_command(record)
      end
      if not record.command_status then
        issue_move(record, group, record.support_position, SUPPORT_RETURN_RADIUS)
      end
    end
    return
  end

  if ensure_entry_traversed(record, group, site) then
    return
  end

  local follow_position = find_support_follow_position(group, site, turret)
  local target_changed = not record.target_turret_position
    or distance_sq(record.target_turret_position, turret.position) > 1
  record.target_turret_name = turret.name
  record.target_turret_position = copy_position(turret.position)
  record.target_force_name = site.defense_force_name

  if target_changed then
    record_debug_event("support_followup_started", record, {
      reason = melee_record and "melee-close" or "follow",
      target_turret_name = turret.name,
      target_turret_position = turret.position,
      entry_open = true
    })
  end

  if command_finished(record, group) then
    clear_command(record)
  end

  if follow_position and distance_sq(group.position, follow_position) > 9 then
    if not record.command_status or record.command_kind ~= "move" then
      issue_move(record, group, follow_position, 2)
    end
  elseif not record.command_status or record.command_kind ~= "attack" then
    issue_attack_entity(record, group, turret)
  end
end

function handle_support_group(record, group)
  if count_group_members(group) == 0 then
    remove_group_record(record.id, false, "support-empty")
    return
  end

  if record.activated_tick and game.tick - record.activated_tick > MAX_SCRIPT_CONTROL_TICKS then
    start_fallback_attack(record, group, "support-timeout")
    return
  end

  if record.state == "support-moving" then
    if command_finished(record, group) then
      local move_failed = record.command_kind == "move"
        and record.support_position
        and distance_sq(group.position, record.support_position) > SUPPORT_RETURN_RADIUS * SUPPORT_RETURN_RADIUS
      clear_command(record)
      if move_failed then
        record_debug_event("command_reasserted", record, {
          reason = "support-moving-command-failed",
          target_position = record.support_position,
          command_kind = "move",
          command_distraction = defines.distraction.none,
          command_target_position = record.support_position,
          script_command_preserved = false
        })
        issue_safe_move(record, group, record.support_position, 3, "support-moving-covered")
        return
      end

      local site = get_site_for_record(record)
      if site and runtime_ext.site_has_reusable_entry(site, group.surface) then
        record.entry_open = true
        record.state = "support-following"
      else
        record.state = "support-sieging"
        note_meaningful_progress(record, group.position)
        if not issue_support_breach_attack(record, group) then
          set_group_autonomous(group)
          remove_group_record(record.id, false, "support-no-breach-target")
        end
      end
    elseif not record.command_status then
      issue_safe_move(record, group, record.support_position, 3, "support-moving-covered")
    elseif reassert_move_command(record, group, record.support_position, 3, "support-moving-stuck", true) then
      return
    end
    return
  end

  if record.state == "support-resetting" then
    if command_finished(record, group) then
      local move_failed = record.command_kind == "move"
        and record.support_position
        and distance_sq(group.position, record.support_position) > SUPPORT_RETURN_RADIUS * SUPPORT_RETURN_RADIUS
      clear_command(record)
      if move_failed then
        record_debug_event("command_reasserted", record, {
          reason = "support-reset-command-failed",
          target_position = record.support_position,
          command_kind = "move",
          command_distraction = defines.distraction.none,
          command_target_position = record.support_position,
          script_command_preserved = false
        })
        issue_safe_move(record, group, record.support_position, SUPPORT_RETURN_RADIUS, "support-reset-covered")
        return
      end

      record.state = "support-sieging"
      note_meaningful_progress(record, group.position)
    elseif not record.command_status then
      issue_safe_move(record, group, record.support_position, SUPPORT_RETURN_RADIUS, "support-reset-covered")
    elseif reassert_move_command(record, group, record.support_position, SUPPORT_RETURN_RADIUS, "support-resetting-stuck", true) then
      return
    end
    return
  end

  if record.state == "support-sieging" then
    local breach_open, open_segments = update_breach_progress(record, group.surface)
    local site = get_site_for_record(record)
    if breach_open then
      clear_command(record)
      if site then
        site.entry_open = true
        record.entry_open = true
        record.state = "support-following"
        note_meaningful_progress(record, group.position)
      else
        set_group_autonomous(group)
        remove_group_record(record.id, false, "support-breach-open")
      end
      return
    end

    local drifting = record.support_position
      and distance_sq(group.position, record.support_position) > SUPPORT_MAX_DRIFT * SUPPORT_MAX_DRIFT
    local exposed = record.support_mode ~= "cone-siege"
      and #find_covering_turrets(group.surface, group.force, group.position) > 0

    if drifting or exposed then
      clear_command(record)
      record.state = "support-resetting"
      note_meaningful_progress(record, group.position)
      issue_safe_move(record, group, record.support_position, SUPPORT_RETURN_RADIUS, drifting and "support-drift-covered" or "support-exposed")
      return
    end

    local last_pressure_tick = site and site.last_breach_pressure_tick or record.last_meaningful_progress_tick or game.tick
    if site and open_segments == 0 and game.tick - last_pressure_tick > BREACH_PRESSURE_TIMEOUT and record.last_breach_pressure_lost_tick ~= game.tick then
      record.last_breach_pressure_lost_tick = game.tick
      record_debug_event("breach_pressure_lost", record, {
        reason = "support-sieging-timeout",
        support_mode = record.support_mode,
        breach_pressure_active = false
      })
    end

    if command_finished(record, group) then
      clear_command(record)
      if not issue_support_breach_attack(record, group) then
        if open_segments > 0 then
          set_group_autonomous(group)
          remove_group_record(record.id, false, "support-breach-partial")
        else
          start_fallback_attack(record, group, "support-no-progress")
        end
      end
    elseif not record.command_status then
      if not issue_support_breach_attack(record, group) then
        set_group_autonomous(group)
        remove_group_record(record.id, false, "support-no-target")
      end
    end
    return
  end

  if record.state == "fallback-attack" then
    if command_finished(record, group) or game.tick >= record.fallback_deadline_tick then
      clear_command(record)
      set_group_autonomous(group)
      remove_group_record(record.id, false, "support-fallback-finished")
    end
    return
  end

  if record.state == "support-following" then
    handle_support_following(record, group)
  end
end

function handle_flank_state(record, group)
  if command_finished(record, group) then
    local command_failed = record.command_result == defines.behavior_result.fail
      or record.command_result == defines.behavior_result.deleted
    clear_command(record)

    if command_failed and record.replans >= MAX_REPLANS then
      start_fallback_attack(record, group, "flank-failed")
      return
    end

    record.flank_index = record.flank_index + 1

    if record.flank_index > #record.flank_waypoints then
      record.state = "tracking"
      record.flank_waypoints = nil
      record.flank_index = nil
    else
      issue_move(record, group, record.flank_waypoints[record.flank_index], 2)
    end
  elseif not record.command_status and record.flank_waypoints and record.flank_index then
    issue_safe_move(record, group, record.flank_waypoints[record.flank_index], 2, "flank-waypoint-covered")
  end
end

function handle_rally_state(record, group)
  if record.waiting_for_breach
    and record.rally_position
    and distance_sq(group.position, record.rally_position) <= 9 then
    clear_command(record)
    record.state = "breach-waiting"
    record.breach_wait_started_tick = record.breach_wait_started_tick or game.tick
    note_meaningful_progress(record, group.position)
    return
  end

  if command_finished(record, group) then
    local move_failed = record.command_kind == "move"
      and record.rally_position
      and distance_sq(group.position, record.rally_position) > 9
    clear_command(record)
    if move_failed then
      record_debug_event("command_reasserted", record, {
        reason = "rally-command-failed",
        target_position = record.rally_position,
        command_kind = "move",
        command_distraction = defines.distraction.none,
        command_target_position = record.rally_position,
        script_command_preserved = false
      })
      issue_safe_move(record, group, record.rally_position, 3, "rally-covered")
      return
    end

    if record.waiting_for_breach then
      record.state = "breach-waiting"
    else
      record.state = "attacking"
      issue_attack(record, group, record.target_position, record.target_force_name)
    end
  elseif not record.command_status then
    if record.command_kind and record.command_kind ~= "move" then
      record_debug_event("command_reasserted", record, {
        reason = "rally-safe-move",
        target_position = record.rally_position,
        command_kind = record.command_kind,
        command_distraction = record.command_distraction,
        command_target_position = record.command_target_position,
        script_command_preserved = false
      })
    end
    issue_safe_move(record, group, record.rally_position, 3, "rally-covered")
  elseif reassert_move_command(record, group, record.rally_position, 3, "rally-move-stuck", true) then
    return
  end
end

function handle_breach_wait_state(record, group)
  local breach_open = update_breach_progress(record, group.surface)
  local exposed = #find_covering_turrets(group.surface, group.force, group.position) > 0
  local site = get_site_for_record(record)

  if breach_open then
    record.waiting_for_breach = false
    if start_post_breach_planning(record, group, "breach-open") then
      handle_post_breach_planning(record, group)
    else
      record.state = "attacking"
      record_debug_event("attack_selected", record, {
        reason = "breach-open",
        target_position = record.target_position,
        siege_site_id = record.siege_site_id,
        breach_required_segments = record.breach_required_segments,
        breach_open_segments = record.breach_open_segments
      })
      issue_attack(record, group, record.target_position, record.target_force_name)
    end
    return
  end

  if site and not record.breach_replan_used then
    local last_pressure_tick = site.last_breach_pressure_tick or record.breach_wait_started_tick or record.activated_tick or game.tick
    if game.tick - last_pressure_tick > BREACH_PRESSURE_TIMEOUT and site.support_mode == "safe-standoff" and site.cone_lane_positions and #site.cone_lane_positions > 0 then
      record.last_breach_pressure_lost_tick = game.tick
      record_debug_event("breach_pressure_lost", record, {
        reason = "safe-standoff-timeout",
        support_mode = site.support_mode,
        breach_pressure_active = false
      })
      record.breach_replan_used = true
      record.replans = record.replans + 1
      site.support_mode = "cone-siege"
      site.support_position = copy_position(site.cone_lane_positions[math.ceil(#site.cone_lane_positions / 2)])
      runtime_ext.release_child_support_groups(record.id, "support-mode-replan")
      clear_command(record)
      record_debug_event("support_mode_replanned", record, {
        reason = "breach-pressure-timeout",
        support_mode = site.support_mode,
        target_position = site.support_position
      })
      note_meaningful_progress(record, group.position)
      begin_siege(record, group, site)
      return
    end
  end

  if record.rally_position and (distance_sq(group.position, record.rally_position) > 16 or exposed) then
    if command_finished(record, group) then
      clear_command(record)
    elseif exposed and record.command_kind ~= "move" then
      record_debug_event("command_reasserted", record, {
        reason = "breach-wait-safe-move",
        target_position = record.rally_position,
        command_kind = record.command_kind,
        command_distraction = record.command_distraction,
        command_target_position = record.command_target_position,
        script_command_preserved = false
      })
      clear_command(record)
    end

    if not record.command_status or record.command_kind ~= "move" then
      issue_safe_move(record, group, record.rally_position, 3, "breach-wait-covered")
    elseif reassert_move_command(record, group, record.rally_position, 3, "breach-wait-move-stuck", true) then
      return
    end
  end
end

function handle_attack_state(record, group)
  if record.siege_site_id and record.breach_positions then
    local breach_open = update_breach_progress(record, group.surface)
    if breach_open and start_post_breach_planning(record, group, "attack-breach-open") then
      handle_post_breach_planning(record, group)
      return
    end
  end

  if command_finished(record, group) then
    clear_command(record)
    if record.siege_site_id and record.breach_positions then
      local next_entity, next_position = find_next_breach_target(
        group.surface,
        record.target_force_name,
        record.breach_positions,
        record.breach_attack_order
      )
      if next_entity and next_position then
        issue_attack(record, group, next_position, record.target_force_name)
        return
      end
    end

    set_group_autonomous(group)
    remove_group_record(record.id, false, "attack-finished")
  elseif not record.command_status then
    issue_attack(record, group, record.target_position, record.target_force_name)
  end
end

function handle_breach_exploiting_state(record, group)
  local site = get_site_for_record(record)
  if command_finished(record, group) then
    local previous_command_kind = record.command_kind
    clear_command(record)
    if site and previous_command_kind == "move" then
      issue_breach_exploit(record, group, site, "breach-exploit-refresh")
    else
      set_group_autonomous(group)
      remove_group_record(record.id, false, "breach-exploit-finished")
    end
  elseif not record.command_status and site then
    issue_breach_exploit(record, group, site, "breach-exploit-refresh")
  end
end

function update_record_analysis(record, analysis, reference_position, selected_candidate)
  local selected_key = selected_candidate and selected_candidate.key or nil
  record.debug_candidates, record.debug_selected_candidate_index = build_debug_candidates(analysis, reference_position, selected_key)
  record.debug_analysis = {
    closed = analysis.closed,
    fully_covered = analysis.fully_covered,
    truncated = analysis.truncated,
    candidate_count = #analysis.candidates
  }
end

local function site_rally_is_safe(group, site)
  if not (group and site and site.rally_position) then
    return false, "missing-rally-position"
  end

  local covering_turrets = find_covering_turrets(group.surface, group.force, site.rally_position)
  if #covering_turrets > 0 then
    return false, "siege-rally-covered"
  end

  local path_covered = path_has_turret_coverage(group.surface, group.force, group.position, site.rally_position)
  if path_covered then
    return false, "siege-rally-path-covered"
  end

  return true, nil
end

local function try_activate_flank_route(record, group, flank_waypoints, best_candidate, reason)
  if not (flank_waypoints and #flank_waypoints > 0 and best_candidate and best_candidate.entity and best_candidate.entity.valid) then
    return false
  end

  record.replans = record.replans + 1
  record.target_position = copy_position(best_candidate.position)
  record.target_force_name = best_candidate.entity.force.name
  record.flank_waypoints = flank_waypoints
  record.flank_index = 1
  record.state = "flanking"

  if reason then
    record_debug_event("unsafe_rally_replanned", record, {
      reason = reason,
      target_position = flank_waypoints[1],
      selected_candidate_index = record.debug_selected_candidate_index,
      command_kind = record.command_kind,
      command_distraction = record.command_distraction,
      command_target_position = record.command_target_position
    })
  end

  record_debug_event("flank_waypoint_set", record, {
    reason = reason or "better-flank",
    target_position = flank_waypoints[1],
    selected_candidate_index = record.debug_selected_candidate_index
  })

  if not issue_safe_move(record, group, flank_waypoints[1], 2, "flank-waypoint-covered") then
    record.state = "tracking"
    record.flank_waypoints = nil
    record.flank_index = nil
    return false
  end

  return true
end

local function try_replan_unsafe_rally(record, group, analysis, current_candidate, best_candidate, site)
  if not (site and site.support_mode == "none" and current_candidate and best_candidate and record.replans < MAX_REPLANS) then
    return false
  end

  local rally_safe, unsafe_reason = site_rally_is_safe(group, site)
  if rally_safe then
    return false
  end

  local flank_waypoints = runtime_ext.choose_safe_flank_route(
    group,
    runtime_ext.build_perimeter_flank_waypoints(analysis, current_candidate, best_candidate),
    best_candidate.outside_position
  )
  if #flank_waypoints == 0 then
    return false
  end

  return try_activate_flank_route(record, group, flank_waypoints, best_candidate, unsafe_reason)
end

function plan_group_action(record, group)
  local siege_site = find_nearby_siege_site(group)
  if siege_site then
    begin_siege(record, group, siege_site)
    return
  end

  local nearest_wall = get_nearest_wall(group)
  if not nearest_wall then
    if record.activated_tick then
      remove_group_record(record.id, true, "lost-contact")
    end
    return
  end

  record.last_contact_position = copy_position(nearest_wall.position)
  record_debug_event("contact_found", record, {
    reason = "nearest-wall",
    contact_position = nearest_wall.position
  })

  local analysis = analyze_wall_network(group, nearest_wall)
  record_debug_event("wall_network_scanned", record, {
    reason = analysis.closed and "closed" or "open",
    contact_position = nearest_wall.position,
    candidate_count = #analysis.candidates
  })

  if #analysis.candidates == 0 then
    record.target_position = copy_position(nearest_wall.position)
    record.target_force_name = nearest_wall.force.name
    record.debug_candidates = {}
    record.debug_selected_candidate_index = nil
    record.debug_analysis = {
      closed = analysis.closed,
      fully_covered = analysis.fully_covered,
      truncated = analysis.truncated,
      candidate_count = 0
    }
    record.state = "attacking"
    record_debug_event("candidates_scored", record, {
      reason = "no-candidates",
      candidate_count = 0
    })
    record_debug_event("attack_selected", record, {
      reason = "no-candidates",
      target_position = record.target_position
    })
    issue_attack(record, group, record.target_position, record.target_force_name)
    return
  end

  local current_candidate = choose_contact_candidate(analysis, group.position)
  local best_candidate = choose_best_candidate(analysis, group.position) or current_candidate

  update_record_analysis(record, analysis, group.position, best_candidate)
  record_debug_event("candidates_scored", record, {
    reason = "scored",
    candidate_count = #analysis.candidates,
    selected_candidate_index = record.debug_selected_candidate_index
  })

  if current_candidate and current_candidate.cover_count == 0 then
    local direct_site = get_or_create_siege_site(group, current_candidate, analysis)
    record.target_position = copy_position(current_candidate.position)
    record.target_force_name = current_candidate.entity.force.name
    apply_site_to_record(record, direct_site)
    record.state = "attacking"
    record_debug_event("attack_selected", record, {
      reason = "open-contact",
      target_position = record.target_position,
      selected_candidate_index = record.debug_selected_candidate_index
    })
    issue_attack(record, group, record.target_position, record.target_force_name)
    return
  end

  if current_candidate
    and best_candidate
    and compare_candidate_priority(best_candidate, current_candidate)
    and record.replans < MAX_REPLANS then
    local flank_waypoints = filter_safe_flank_waypoints(
      group,
      build_flank_waypoints(analysis, current_candidate, best_candidate),
      best_candidate.outside_position
    )
    if #flank_waypoints == 0 and current_candidate.cover_count > 0 and best_candidate.cover_count == 0 then
      flank_waypoints = runtime_ext.choose_safe_flank_route(
        group,
        runtime_ext.build_perimeter_flank_waypoints(analysis, current_candidate, best_candidate),
        best_candidate.outside_position
      )
    end
    if #flank_waypoints > 0 then
      if not try_activate_flank_route(record, group, flank_waypoints, best_candidate, "better-flank") then
        local siege_site_record = get_or_create_siege_site(group, best_candidate, analysis)
        begin_siege(record, group, siege_site_record)
      end
      return
    end

    if current_candidate.cover_count > 0 and best_candidate.cover_count == 0 then
      local siege_site_record = get_or_create_siege_site(group, best_candidate, analysis)
      if try_replan_unsafe_rally(record, group, analysis, current_candidate, best_candidate, siege_site_record) then
        return
      end
      begin_siege(record, group, siege_site_record)
      return
    end
  end

  local _, ranged_range = get_group_ranged_members(group)
  if best_candidate and best_candidate.cover_count > 0 and ranged_range > 1.5 then
    local _, support_position = find_staging_positions(group, best_candidate, analysis)
    if support_position then
      local siege_site_record = get_or_create_siege_site(group, best_candidate, analysis)
      if try_replan_unsafe_rally(record, group, analysis, current_candidate, best_candidate, siege_site_record) then
        return
      end
      begin_siege(record, group, siege_site_record)
      return
    end
  end

  if analysis.closed and analysis.fully_covered and best_candidate then
    local siege_site_record = get_or_create_siege_site(group, best_candidate, analysis)
    if try_replan_unsafe_rally(record, group, analysis, current_candidate, best_candidate, siege_site_record) then
      return
    end
    begin_siege(record, group, siege_site_record)
    return
  end

  local fallback_candidate = best_candidate or current_candidate
  local fallback_site = get_or_create_siege_site(group, fallback_candidate, analysis)
  record.target_position = copy_position(fallback_candidate.position)
  record.target_force_name = fallback_candidate.entity.force.name
  apply_site_to_record(record, fallback_site)
  record.state = "attacking"
  record_debug_event("attack_selected", record, {
    reason = "best-candidate",
    target_position = record.target_position,
    selected_candidate_index = record.debug_selected_candidate_index
  })
  issue_attack(record, group, record.target_position, record.target_force_name)
end

function process_group_record(record_id)
  local record = storage.group_ai[record_id]
  if not record then
    return
  end

  local group = get_group(record)
  if not group then
    remove_group_record(record_id, false, "group-invalid")
    return
  end

  record.last_seen_tick = game.tick
  record.last_position = copy_position(group.position)
  record.surface_name = group.surface.name
  sync_record_runtime_state(record, group)

  local is_debug_arena_group = record.scenario ~= nil and group.surface.name == DEBUG_ARENA_SURFACE_NAME

  if record.role ~= "support"
    and record.role ~= "assault"
    and record.role ~= "reserve"
    and group.is_unit_group
    and group.state == defines.group_state.gathering
    and record.state == "tracking"
    and not is_debug_arena_group then
    return
  end

  if count_group_members(group) == 0 then
    remove_group_record(record_id, false, "group-empty")
    return
  end

  if record.activated_tick
    and game.tick - record.activated_tick > MAX_SCRIPT_CONTROL_TICKS
    and record.state ~= "fallback-attack" then
    start_fallback_attack(record, group, "script-control-timeout")
    return
  end

  if handle_state_stall(record, group) then
    return
  end

  if record.role == "support" then
    handle_support_group(record, group)
    return
  end

  if record.state == "flanking" then
    handle_flank_state(record, group)
    return
  end

  if record.state == "rallying" then
    handle_rally_state(record, group)
    return
  end

  if record.state == "breach-waiting" then
    handle_breach_wait_state(record, group)
    return
  end

  if record.state == "post-breach-planning" then
    handle_post_breach_planning(record, group)
    return
  end

  if record.state == "assault-staging" or record.state == "assault-engaging" then
    handle_assault_state(record, group)
    return
  end

  if record.state == "breach-exploiting" then
    handle_breach_exploiting_state(record, group)
    return
  end

  if record.state == "attacking" then
    handle_attack_state(record, group)
    return
  end

  if record.state == "fallback-attack" then
    if command_finished(record, group) or game.tick >= record.fallback_deadline_tick then
      clear_command(record)
      set_group_autonomous(group)
      remove_group_record(record.id, false, "fallback-finished")
    end
    return
  end

  plan_group_action(record, group)
end

do
function draw_debug_overlay()
  clear_debug_overlay()

  local player_contexts = get_overlay_player_contexts()
  local player_indices = {}
  for index = 1, #player_contexts do
    player_indices[index] = player_contexts[index].player_index
  end

  if #player_indices == 0 then
    return
  end

  local rendered_sites = 0
  for _, site in pairs(storage.siege_sites) do
    local surface = game.surfaces[site.surface_index]
    if surface
      and overlay_surface_is_visible(player_contexts, site.surface_index)
      and overlay_position_is_visible(player_contexts, site.surface_index, site.target_position) then
      rendering.draw_circle({
        color = {r = 1, g = 0.75, b = 0.1},
        radius = 1.1,
        width = 2,
        filled = false,
        target = site.target_position,
        surface = surface,
        players = player_indices,
        time_to_live = PROCESS_INTERVAL + 5,
        draw_on_ground = true
      })

      if site.entry_position then
        rendering.draw_circle({
          color = {r = 0.25, g = 0.9, b = 1},
          radius = 0.9,
          width = 2,
          filled = false,
          target = site.entry_position,
          surface = surface,
          players = player_indices,
          time_to_live = PROCESS_INTERVAL + 5,
          draw_on_ground = true
        })
      end

      rendered_sites = rendered_sites + 1
      if rendered_sites >= DEBUG_OVERLAY_SITE_LIMIT then
        break
      end
    end
  end

  local rendered_groups = 0
  for _, record in pairs(storage.group_ai) do
    local group = get_group(record)
    if group
      and overlay_position_is_visible(player_contexts, group.surface.index, group.position) then
      local label_position = {
        x = group.position.x,
        y = group.position.y - 1.5
      }

      rendering.draw_text({
        text = string.format("ABT %s #%d r=%d", record.state or "?", record.id, record.replans or 0),
        surface = group.surface,
        target = label_position,
        color = {r = 0.85, g = 1, b = 0.85},
        scale = 1.1,
        players = player_indices,
        time_to_live = PROCESS_INTERVAL + 5
      })

      if record.target_position then
        rendering.draw_line({
          color = {r = 0.25, g = 1, b = 0.25},
          width = 2,
          from = group.position,
          to = record.target_position,
          surface = group.surface,
          players = player_indices,
          time_to_live = PROCESS_INTERVAL + 5,
          draw_on_ground = true
        })
      end

      if record.target_turret_position then
        rendering.draw_circle({
          color = record.target_turret_name == "flamethrower-turret"
            and {r = 1, g = 0.55, b = 0.1}
            or {r = 1, g = 0.9, b = 0.1},
          radius = 0.65,
          width = 2,
          filled = false,
          target = record.target_turret_position,
          surface = group.surface,
          players = player_indices,
          time_to_live = PROCESS_INTERVAL + 5,
          draw_on_ground = true
        })
      end

      if record.lane_positions then
        for index = 1, #record.lane_positions do
          rendering.draw_circle({
            color = index == record.lane_index and {r = 0.2, g = 0.8, b = 1} or {r = 0.3, g = 0.45, b = 0.9},
            radius = 0.35,
            width = 2,
            filled = false,
            target = record.lane_positions[index],
            surface = group.surface,
            players = player_indices,
            time_to_live = PROCESS_INTERVAL + 5,
            draw_on_ground = true
          })
        end
      end

      if record.hazard_positions then
        for index = 1, #record.hazard_positions do
          rendering.draw_circle({
            color = {r = 1, g = 0.2, b = 0.2},
            radius = 0.3,
            width = 2,
            filled = false,
            target = record.hazard_positions[index],
            surface = group.surface,
            players = player_indices,
            time_to_live = PROCESS_INTERVAL + 5,
            draw_on_ground = true
          })
        end
      end

      if record.flank_waypoints then
        local previous = copy_position(group.position)
        for index = 1, #record.flank_waypoints do
          local waypoint = record.flank_waypoints[index]
          rendering.draw_line({
            color = {r = 0.25, g = 0.8, b = 1},
            width = 2,
            from = previous,
            to = waypoint,
            surface = group.surface,
            players = player_indices,
            time_to_live = PROCESS_INTERVAL + 5,
            draw_on_ground = true
          })
          previous = waypoint
        end
      end

      if record.debug_candidates then
        local limit = math.min(DEBUG_OVERLAY_CANDIDATE_LIMIT, #record.debug_candidates)
        for index = 1, limit do
          local candidate = record.debug_candidates[index]
          rendering.draw_circle({
            color = candidate.selected and {r = 0.1, g = 1, b = 0.1} or {r = 1, g = 0.2, b = 0.2},
            radius = 0.45,
            width = 2,
            filled = false,
            target = candidate.position,
            surface = group.surface,
            players = player_indices,
            time_to_live = PROCESS_INTERVAL + 5,
            draw_on_ground = true
          })
        end
      end

      rendered_groups = rendered_groups + 1
      if rendered_groups >= DEBUG_OVERLAY_GROUP_LIMIT then
        break
      end
    end
  end
end

function process_tracked_groups()
  ensure_globals()
  process_debug_arena_waves()
  prune_siege_sites()

  local queue = storage.group_queue
  local queue_size = #queue

  if queue_size > 0 then
    local processed = 0
    local cursor = storage.group_queue_index

    while processed < MAX_GROUPS_PER_PASS and queue_size > 0 do
      if cursor > queue_size then
        cursor = 1
      end

      local record_id = queue[cursor]
      if record_id and storage.group_ai[record_id] then
        process_group_record(record_id)
      elseif record_id then
        table.remove(queue, cursor)
        queue_size = queue_size - 1
        cursor = cursor - 1
      end

      processed = processed + 1
      cursor = cursor + 1
    end

    if queue_size == 0 then
      storage.group_queue_index = 1
    else
      if cursor > queue_size then
        cursor = 1
      end
      storage.group_queue_index = cursor
    end
  end

  if is_debug_capture_enabled() then
    write_latest_snapshot("interval")
  end

  if #get_overlay_player_indices() > 0 then
    draw_debug_overlay()
  else
    clear_debug_overlay()
  end
end

function get_debug_status()
  ensure_globals()

  local tracked = 0
  local active = 0

  for _, record in pairs(storage.group_ai) do
    tracked = tracked + 1
    if record.activated_tick or record.state ~= "tracking" then
      active = active + 1
    end
  end

  local siege_site_count = 0
  for _ in pairs(storage.siege_sites) do
    siege_site_count = siege_site_count + 1
  end

  return {
    tracked = tracked,
    active = active,
    siege_sites = siege_site_count,
    debug_players = get_debug_player_indices()
  }
end

set_debug_enabled = function(player_index, enabled)
  ensure_globals()

  if player_index == 0 then
    storage.debug.server_capture = enabled
    return
  end

  if enabled then
    storage.debug.enabled_players[player_index] = true
  else
    storage.debug.enabled_players[player_index] = nil
  end
end

clear_debug_runtime = function()
  ensure_globals()
  storage.debug.recent_events = {}
  storage.debug.scenario_events = {}

  for _, record in pairs(storage.group_ai) do
    record.debug_candidates = nil
    record.debug_selected_candidate_index = nil
    record.debug_analysis = nil
    record.last_contact_position = nil
  end

  clear_debug_overlay()
  helpers.remove_path(DEBUG_DIR)
end

require_admin_or_server = function(command)
  if not command.player_index then
    return nil, true
  end

  local player = game.get_player(command.player_index)
  if player and player.valid and player.admin then
    return player, true
  end

  if player and player.valid then
    player.print({"advanced-biter-tactics.debug-not-admin"})
  end

  return player, false
end

parse_command_parameter = function(parameter)
  local trimmed = (parameter or ""):match("^%s*(.-)%s*$")
  if trimmed == "" then
    return ""
  end
  return helpers.multilingual_to_lower(trimmed)
end

write_manual_dump = function(reason)
  write_latest_snapshot(reason)
  write_arena_manifest()
end

runtime_ext.setup_agent_bridge_scenario = function(scenario_name, player_index, options)
  ensure_globals()

  local scenario = DEBUG_SCENARIOS[scenario_name]
  if not scenario then
    error("unknown advanced-biter-tactics debug arena scenario: " .. tostring(scenario_name))
  end

  local player = player_index and game.get_player(player_index) or nil
  local surface = arena_runtime.get_or_create_debug_surface()
  purge_surface_runtime_state(surface.index)
  arena_runtime.clear_debug_surface(surface)
  clear_debug_runtime()
  storage.debug.arena = nil
  set_debug_enabled(0, true)

  if player_index then
    set_debug_enabled(player_index, true)
  end

  local wall_anchor_positions = arena_runtime.build_wall_segments(surface, "player", scenario)
  local turret_positions = arena_runtime.build_turrets(surface, "player", scenario)
  local structure_positions = arena_runtime.build_structures(surface, "player", scenario)
  arena_runtime.seed_reuse_site(surface, scenario)
  arena_runtime.build_debug_arena_manifest(surface, scenario, wall_anchor_positions, turret_positions, structure_positions)

  local scenario_waves = scenario.waves or {{
    delay = 0,
    spawn_position = scenario.spawn_position,
    target_position = scenario.target_position,
    units = scenario.units
  }}

  if #scenario_waves > 0 then
    storage.debug.arena.pending_waves = {}
    for wave_index = 1, #scenario_waves do
      local wave = scenario_waves[wave_index]
      if (wave.delay or 0) <= 0 then
        arena_runtime.spawn_debug_group(surface, scenario, wave, wave_index)
        storage.debug.arena.spawned_wave_count = storage.debug.arena.spawned_wave_count + 1
      else
        storage.debug.arena.pending_waves[#storage.debug.arena.pending_waves + 1] = {
          index = wave_index,
          spawn_tick = game.tick + (wave.delay or 0),
          spawn_position = copy_position(wave.spawn_position),
          target_position = copy_position(wave.target_position),
          units = wave.units
        }
      end
    end

    for _, site in pairs(storage.siege_sites) do
      if site.surface_index == surface.index then
        site.wave_count = storage.debug.arena.spawned_wave_count
      end
    end
  end

  if player and player.valid then
    player.teleport(scenario.observe_position, surface)
    arena_runtime.chart_debug_surface(surface, player)
  end

  write_manual_dump(options and options.reason or "agent-bridge-setup")

  return {
    scenario_name = scenario.name,
    surface_name = surface.name,
    observe_position = serialize_position(scenario.observe_position),
    spawn_position = serialize_position(scenario.spawn_position),
    target_position = serialize_position(scenario.target_position),
    expected_support_mode = scenario.expected_support_mode,
    expected_reuse_wave_count = scenario.expected_reuse_wave_count,
    expected_event_sequence = scenario.expected_event_sequence
  }
end

function command_debug(command)
  ensure_globals()
  local player, allowed = require_admin_or_server(command)
  if not allowed then
    return
  end

  local mode = parse_command_parameter(command.parameter)
  local target_index = command.player_index or 0

  if mode == "on" then
    set_debug_enabled(target_index, true)
    write_manual_dump("debug-on")
    if player then
      player.print({"advanced-biter-tactics.debug-enabled"})
    else
      game.print({"advanced-biter-tactics.debug-enabled-server"})
    end
    return
  end

  if mode == "off" then
    set_debug_enabled(target_index, false)
    if not is_debug_capture_enabled() then
      clear_debug_overlay()
    end
    if player then
      player.print({"advanced-biter-tactics.debug-disabled"})
    else
      game.print({"advanced-biter-tactics.debug-disabled-server"})
    end
    return
  end

  if mode == "status" then
    local status = get_debug_status()
    local recipient = player or game
    recipient.print({"advanced-biter-tactics.status-summary",
      #status.debug_players,
      status.tracked,
      status.active,
      status.siege_sites
    })

    local first_event_index = math.max(1, #storage.debug.recent_events - DEBUG_STATUS_EVENT_LIMIT + 1)
    for index = first_event_index, #storage.debug.recent_events do
      local event = storage.debug.recent_events[index]
      recipient.print({"advanced-biter-tactics.status-event",
        event.tick or 0,
        event.event or "-",
        event.group_id or 0,
        event.state or "-",
        event.target_position and format_number(event.target_position.x) or "-",
        event.target_position and format_number(event.target_position.y) or "-"
      })
    end
    return
  end

  if mode == "dump" then
    write_manual_dump("manual-dump")
    if player then
      player.print({"advanced-biter-tactics.debug-dumped", DEBUG_FILES.snapshot, DEBUG_FILES.events})
    else
      game.print({"advanced-biter-tactics.debug-dumped", DEBUG_FILES.snapshot, DEBUG_FILES.events})
    end
    return
  end

  if mode == "clear" then
    clear_debug_runtime()
    if player then
      player.print({"advanced-biter-tactics.debug-cleared"})
    else
      game.print({"advanced-biter-tactics.debug-cleared"})
    end
    return
  end

  if player then
    player.print({"advanced-biter-tactics.debug-help"})
  else
    game.print({"advanced-biter-tactics.debug-help"})
  end
end

commands.add_command("abt-debug", {"advanced-biter-tactics.command-help-debug"}, command_debug)
script.on_nth_tick(PROCESS_INTERVAL, process_tracked_groups)
end

do
arena_runtime = {}

function arena_runtime.get_or_create_debug_surface()
  local surface = game.surfaces[DEBUG_ARENA_SURFACE_NAME]
  if surface and surface.valid then
    return surface
  end

  surface = game.create_surface(DEBUG_ARENA_SURFACE_NAME, {
    width = 256,
    height = 256,
    peaceful_mode = true,
    starting_area = "none",
    autoplace_controls = {
      ["enemy-base"] = {frequency = "none", size = "none", richness = "none"},
      ["trees"] = {frequency = "none", size = "none", richness = "none"},
      ["coal"] = {frequency = "none", size = "none", richness = "none"},
      ["copper-ore"] = {frequency = "none", size = "none", richness = "none"},
      ["crude-oil"] = {frequency = "none", size = "none", richness = "none"},
      ["iron-ore"] = {frequency = "none", size = "none", richness = "none"},
      ["stone"] = {frequency = "none", size = "none", richness = "none"},
      ["uranium-ore"] = {frequency = "none", size = "none", richness = "none"}
    }
  })

  surface.request_to_generate_chunks({0, 0}, 6)
  surface.force_generate_chunk_requests()
  surface.daytime = 0.5
  surface.freeze_daytime = true
  return surface
end

function arena_runtime.clear_debug_surface(surface)
  local entities = surface.find_entities()
  for index = 1, #entities do
    local entity = entities[index]
    if entity.valid and entity.type ~= "character" then
      entity.destroy()
    end
  end

  surface.destroy_decoratives({
    area = {
      left_top = {-DEBUG_ARENA_TILE_HALF_SIZE, -DEBUG_ARENA_TILE_HALF_SIZE},
      right_bottom = {DEBUG_ARENA_TILE_HALF_SIZE, DEBUG_ARENA_TILE_HALF_SIZE}
    }
  })

  local tiles = {}
  for x = -DEBUG_ARENA_TILE_HALF_SIZE, DEBUG_ARENA_TILE_HALF_SIZE do
    for y = -DEBUG_ARENA_TILE_HALF_SIZE, DEBUG_ARENA_TILE_HALF_SIZE do
      tiles[#tiles + 1] = {
        name = "concrete",
        position = {x = x, y = y}
      }
    end
  end
  surface.set_tiles(tiles)
end

function arena_runtime.chart_debug_surface(surface, player)
  if player and player.valid then
    player.force.chart(surface, {
      left_top = {-DEBUG_ARENA_TILE_HALF_SIZE, -DEBUG_ARENA_TILE_HALF_SIZE},
      right_bottom = {DEBUG_ARENA_TILE_HALF_SIZE, DEBUG_ARENA_TILE_HALF_SIZE}
    })
  end
end

function arena_runtime.iterate_line(from_position, to_position)
  local positions = {}
  local dx = to_position.x - from_position.x
  local dy = to_position.y - from_position.y
  local steps = math.max(math.abs(dx), math.abs(dy))

  for step = 0, steps do
    positions[#positions + 1] = {
      x = from_position.x + dx * step / steps,
      y = from_position.y + dy * step / steps
    }
  end

  return positions
end

function arena_runtime.build_wall_segments(surface, force_name, scenario)
  local wall_positions = {}

  for segment_index = 1, #scenario.walls do
    local segment = scenario.walls[segment_index]
    local line_positions = arena_runtime.iterate_line(segment.from, segment.to)

    for position_index = 1, #line_positions do
      local position = line_positions[position_index]
      local key = position_key(position)
      if not wall_positions[key] then
        wall_positions[key] = copy_position(position)
        surface.create_entity({
          name = "stone-wall",
          position = position,
          force = force_name
        })
      end
    end
  end

  local anchors = {}
  for _, position in pairs(wall_positions) do
    anchors[#anchors + 1] = serialize_position(position)
  end

  table.sort(anchors, function(left, right)
    if left.x == right.x then
      return left.y < right.y
    end
    return left.x < right.x
  end)

  return anchors
end

function arena_runtime.build_turrets(surface, force_name, scenario)
  local turret_positions = {}

  for index = 1, #scenario.turrets do
    local turret_data = scenario.turrets[index]
    local turret = surface.create_entity({
      name = turret_data.name or "gun-turret",
      position = turret_data.position,
      force = force_name,
      direction = turret_data.direction
    })

    if turret and turret.valid then
      if turret_data.direction and turret.supports_direction then
        turret.direction = turret_data.direction
      end
      if turret_data.ammo and turret.insert then
        turret.insert({name = "piercing-rounds-magazine", count = turret_data.ammo})
      end
      local pipe_position
      if turret.name == "flamethrower-turret" then
        local fuel_name = turret_data.fuel_name or "light-oil"
        local connection_index = turret_data.pipe_connection_index or 1
        local pipe_connections = turret.fluidbox and turret.fluidbox.get_pipe_connections and turret.fluidbox.get_pipe_connections(1) or nil

        if pipe_connections then
          for pipe_index = connection_index, #pipe_connections do
            local connection = pipe_connections[pipe_index]
            local pipe_target = connection and connection.target_position or nil
            if pipe_target then
              local pipe = surface.create_entity({
                name = "infinity-pipe",
                position = pipe_target,
                force = force_name,
                infinity_settings = {
                  name = fuel_name,
                  percentage = 1,
                  mode = "at-least"
                }
              })

              if pipe and pipe.valid then
                pipe.destructible = false
                pipe.minable = false
                if pipe.set_infinity_pipe_filter then
                  pipe.set_infinity_pipe_filter({
                    name = fuel_name,
                    percentage = 1,
                    mode = "at-least"
                  })
                end
                pipe_position = serialize_position(pipe.position)
                break
              end
            end
          end
        end

        if not pipe_position and turret.insert_fluid then
          turret.insert_fluid({
            name = fuel_name,
            amount = 400
          })
        end
      elseif turret_data.fluid and turret.insert_fluid then
        turret.insert_fluid(turret_data.fluid)
      end
      turret_positions[#turret_positions + 1] = {
        name = turret.name,
        position = serialize_position(turret.position),
        direction = turret.direction,
        fuel_name = turret_data.fuel_name,
        pipe_position = pipe_position
      }
    end
  end

  return turret_positions
end

function arena_runtime.build_structures(surface, force_name, scenario)
  local structure_positions = {}

  for index = 1, #(scenario.structures or {}) do
    local structure_data = scenario.structures[index]
    local structure = surface.create_entity({
      name = structure_data.name,
      position = structure_data.position,
      force = force_name,
      direction = structure_data.direction
    })

    if structure and structure.valid then
      structure_positions[#structure_positions + 1] = {
        name = structure.name,
        position = serialize_position(structure.position)
      }
    end
  end

  return structure_positions
end

function arena_runtime.build_wave_manifest(scenario)
  local waves = {}
  local scenario_waves = scenario.waves or {{
    delay = 0,
    spawn_position = scenario.spawn_position,
    target_position = scenario.target_position,
    units = scenario.units
  }}

  for index = 1, #scenario_waves do
    local wave = scenario_waves[index]
    waves[#waves + 1] = {
      index = index,
      delay = wave.delay or 0,
      spawn_position = serialize_position(wave.spawn_position),
      target_position = serialize_position(wave.target_position),
      units = wave.units
    }
  end

  return waves
end

function arena_runtime.spawn_debug_group(surface, scenario, wave_data, wave_index)
  local spawn_position = wave_data and wave_data.spawn_position or scenario.spawn_position
  local target_position = wave_data and wave_data.target_position or scenario.target_position
  local units = wave_data and wave_data.units or scenario.units
  local group = surface.create_unit_group({
    position = spawn_position,
    force = "enemy"
  })
  if not (group and group.valid) then
    return nil
  end

  local unit_index = 0
  for stack_index = 1, #units do
    local unit_stack = units[stack_index]
    for _ = 1, unit_stack.count do
      unit_index = unit_index + 1
      local offset = ((unit_index - 1) % 4) * 0.6
      local row = math.floor((unit_index - 1) / 4) * 0.6
      local position = {
        x = spawn_position.x - row,
        y = spawn_position.y - 1 + offset
      }

      local unit = surface.create_entity({
        name = unit_stack.name,
        position = position,
        force = "enemy"
      })

      if unit and unit.valid then
        group.add_member(unit)
      end
    end
  end

  local record = storage.group_ai[group.unique_id] or register_group(group, "main", nil, scenario.name)
  if record then
    record.state = "tracking"
    record.wave_index = wave_index
    record_debug_event("arena_wave_spawned", record, {
      reason = wave_index and ("wave-" .. wave_index) or "wave",
      scenario = scenario.name,
      wave_index = wave_index,
      target_position = target_position
    })
  end

  return group
end

function arena_runtime.build_debug_arena_manifest(surface, scenario, wall_anchor_positions, turret_positions, structure_positions)
  storage.debug.arena = {
    scenario = scenario.name,
    surface_name = surface.name,
    observe_position = serialize_position(scenario.observe_position),
    spawn_position = serialize_position(scenario.spawn_position),
    target_position = serialize_position(scenario.target_position),
    wall_anchor_positions = wall_anchor_positions,
    turret_positions = turret_positions,
    structure_positions = structure_positions,
    waves = arena_runtime.build_wave_manifest(scenario),
    pending_waves = {},
    spawned_wave_count = 0,
    open_breach_positions = serialize_positions(scenario.open_breach_positions),
    expected_support_mode = scenario.expected_support_mode,
    expected_reuse_wave_count = scenario.expected_reuse_wave_count,
    expected_behavior = scenario.expected_behavior,
    expected_event_sequence = scenario.expected_event_sequence
  }

  write_arena_manifest()
end

process_debug_arena_waves = function()
  local arena = storage.debug.arena
  if not (arena and arena.pending_waves and #arena.pending_waves > 0) then
    return
  end

  local surface = game.surfaces[arena.surface_name]
  if not surface then
    return
  end

  local index = 1
  while index <= #arena.pending_waves do
    local wave = arena.pending_waves[index]
    if wave.spawn_tick <= game.tick then
      arena_runtime.spawn_debug_group(surface, DEBUG_SCENARIOS[arena.scenario], wave, wave.index)
      arena.spawned_wave_count = (arena.spawned_wave_count or 0) + 1

      for _, site in pairs(storage.siege_sites) do
        if site.surface_index == surface.index then
          site.wave_count = arena.spawned_wave_count
        end
      end

      table.remove(arena.pending_waves, index)
    else
      index = index + 1
    end
  end
end

function arena_runtime.seed_reuse_site(surface, scenario)
  if not scenario.reuse_site then
    return
  end

  local breach_positions = copy_positions(scenario.open_breach_positions)
  local breach_center = average_positions(breach_positions) or {x = 0, y = 0}
  local site_key = make_site_key(surface.index, breach_center)
  local site = {
    key = site_key,
    surface_index = surface.index,
    defense_force_name = "player",
    target_position = copy_position(breach_center),
    approach_side = "west",
    rally_position = {x = breach_center.x - BREACH_ENTRY_DISTANCE, y = breach_center.y},
    support_position = {x = breach_center.x - (BREACH_ENTRY_DISTANCE + 3), y = breach_center.y},
    support_mode = "none",
    breach_positions = breach_positions,
    breach_attack_order = copy_positions(breach_positions),
    breach_required_segments = math.min(DESIRED_BREACH_SEGMENTS, #breach_positions),
    breach_axis = "vertical",
    probe_unit_name = UNIT_PROBE_FALLBACK,
    entry_open = true,
    entry_clear = true,
    cone_lane_positions = {},
    assault_targets = {},
    assault_group_ids = {},
    cone_group_ids = {},
    reserve_group_ids = {},
    last_breach_pressure_tick = nil,
    wave_count = 0,
    expires_tick = game.tick + SIEGE_SITE_TTL
  }

  storage.siege_sites[site_key] = site
  update_site_entry_positions(site, surface)
  if scenario.target_position then
    site.seeded_inside_rally_position = copy_position(scenario.target_position)
    site.seeded_exploit_position = copy_position(scenario.target_position)
    site.inside_rally_position = copy_position(scenario.target_position)
    site.exploit_position = copy_position(scenario.target_position)
  end
  site.wave_count = 0
  collect_local_assault_targets(surface, site)
end

function command_debug_arena(command)
  ensure_globals()
  local player, allowed = require_admin_or_server(command)
  if not allowed then
    return
  end

  local scenario_name = parse_command_parameter(command.parameter)
  local scenario = DEBUG_SCENARIOS[scenario_name]
  if not scenario then
    if player then
      player.print({"advanced-biter-tactics.debug-arena-help"})
    else
      game.print({"advanced-biter-tactics.debug-arena-help"})
    end
    return
  end

  local setup = runtime_ext.setup_agent_bridge_scenario(scenario_name, command.player_index, {reason = "arena-created"})
  local surface = game.surfaces[setup.surface_name]

  if player and player.valid then
    player.print({"advanced-biter-tactics.debug-arena-created",
      scenario.name,
      surface.name,
      format_number(scenario.spawn_position.x),
      format_number(scenario.spawn_position.y),
      format_number(scenario.target_position.x),
      format_number(scenario.target_position.y)
    })
    player.print({"advanced-biter-tactics.debug-arena-expected", scenario.expected_behavior})
    if scenario.expected_support_mode then
      player.print({"advanced-biter-tactics.debug-arena-support-mode", scenario.expected_support_mode})
    end
    if scenario.expected_reuse_wave_count then
      player.print({"advanced-biter-tactics.debug-arena-wave-count", scenario.expected_reuse_wave_count})
    end
  else
    game.print({"advanced-biter-tactics.debug-arena-created",
      scenario.name,
      surface.name,
      format_number(scenario.spawn_position.x),
      format_number(scenario.spawn_position.y),
      format_number(scenario.target_position.x),
      format_number(scenario.target_position.y)
    })
    game.print({"advanced-biter-tactics.debug-arena-expected", scenario.expected_behavior})
    if scenario.expected_support_mode then
      game.print({"advanced-biter-tactics.debug-arena-support-mode", scenario.expected_support_mode})
    end
    if scenario.expected_reuse_wave_count then
      game.print({"advanced-biter-tactics.debug-arena-wave-count", scenario.expected_reuse_wave_count})
    end
  end
end

commands.add_command("abt-debug-arena", {"advanced-biter-tactics.command-help-arena"}, command_debug_arena)

remote.add_interface("agent_bridge", {
  list_scenarios = function()
    local scenarios = {}
    for name, scenario in pairs(DEBUG_SCENARIOS) do
      scenarios[#scenarios + 1] = {
        name = name,
        observe_position = serialize_position(scenario.observe_position),
        spawn_position = serialize_position(scenario.spawn_position),
        target_position = serialize_position(scenario.target_position),
        expected_support_mode = scenario.expected_support_mode,
        expected_reuse_wave_count = scenario.expected_reuse_wave_count,
        expected_behavior = scenario.expected_behavior,
        expected_event_sequence = scenario.expected_event_sequence
      }
    end

    table.sort(scenarios, function(left, right)
      return left.name < right.name
    end)

    return scenarios
  end,
  setup_scenario = function(name, options)
    return runtime_ext.setup_agent_bridge_scenario(name, nil, options)
  end,
  capture_frame = function(options)
    ensure_globals()

    local arena = storage.debug.arena
    if not arena then
      return nil
    end

    local surface = arena.surface_name and game.surfaces[arena.surface_name] or nil
    if not surface then
      return nil
    end

    local radius = options and tonumber(options.radius) or 48
    local center = arena.observe_position or arena.spawn_position or {x = 0, y = 0}
    local bounds = {
      left_top = {
        x = center.x - radius,
        y = center.y - radius
      },
      right_bottom = {
        x = center.x + radius,
        y = center.y + radius
      }
    }

    local visible_entities = {}
    local entities = surface.find_entities_filtered({area = bounds})
    for index = 1, #entities do
      visible_entities[#visible_entities + 1] = runtime_ext.serialize_visible_entity(entities[index])
    end

    local groups = {}
    for _, record in pairs(storage.group_ai) do
      if record.scenario == arena.scenario then
        groups[#groups + 1] = serialize_record(record)
      end
    end

    local siege_sites = {}
    for _, site in pairs(storage.siege_sites) do
      if site.surface_index == surface.index then
        siege_sites[#siege_sites + 1] = serialize_site(site)
      end
    end

    return {
      tick = game.tick,
      mod_name = MOD_NAME,
      scenario_name = arena.scenario,
      reason = options and options.reason or "capture",
      active_surface = surface.name,
      viewport = {
        center = serialize_position(center),
        radius = radius,
        bounds = serialize_bounds(bounds)
      },
      visible_entities = visible_entities,
      alerts = {},
      sounds = {},
      gui = {
        root = "none",
        children = {}
      },
      scenario_markers = {
        observe_position = serialize_position(arena.observe_position),
        spawn_position = serialize_position(arena.spawn_position),
        target_position = serialize_position(arena.target_position),
        open_breach_positions = serialize_positions(arena.open_breach_positions),
        viewport_hint = runtime_ext.serialize_area_from_center(center, radius)
      },
      groups = groups,
      siege_sites = siege_sites,
      recent_events = runtime_ext.get_recent_scenario_events(arena.scenario)
    }
  end,
  evaluate_assertions = function(name, options)
    ensure_globals()

    local arena = storage.debug.arena
    local scenario_name = name or (arena and arena.scenario) or nil
    local scenario = scenario_name and DEBUG_SCENARIOS[scenario_name] or nil
    local assertions = {}
    local events = runtime_ext.get_recent_scenario_events(scenario_name)
    local has_arena = arena ~= nil and scenario ~= nil and arena.scenario == scenario_name

    assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
      "arena-created",
      "invariant",
      has_arena,
      true,
      has_arena,
      {
        scenario_name = scenario_name,
        active_scenario = arena and arena.scenario or nil
      }
    )

    if scenario then
      local function find_first_event(event_name, predicate)
        for index = 1, #events do
          local event = events[index]
          if event.event == event_name and (not predicate or predicate(event)) then
            return event, index
          end
        end
        return nil, nil
      end

      local function has_event(event_name, predicate)
        return find_first_event(event_name, predicate) ~= nil
      end

      local actual_event_names = {}
      for index = 1, #events do
        actual_event_names[index] = events[index].event
      end

      local matches_sequence, matched, missing = runtime_ext.event_sequence_matches(events, scenario.expected_event_sequence or {})
      assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
        "expected-event-sequence",
        "sequence",
        matches_sequence,
        scenario.expected_event_sequence,
        actual_event_names,
        {
          matched = matched,
          missing = missing
        }
      )

      if scenario.expected_support_mode then
        local actual_support_mode = nil
        local arena_surface = arena and game.surfaces[arena.surface_name] or nil
        for _, site in pairs(storage.siege_sites) do
          if arena_surface and site.surface_index == arena_surface.index and site.support_mode ~= nil and site.support_mode ~= "none" then
            actual_support_mode = site.support_mode
            break
          end
        end
        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "support-mode",
          "outcome",
          actual_support_mode == scenario.expected_support_mode,
          scenario.expected_support_mode,
          actual_support_mode,
          options or {}
        )
      end

      if scenario.expected_reuse_wave_count then
        local actual_wave_count = arena and arena.spawned_wave_count or 0
        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "reuse-wave-count",
          "outcome",
          actual_wave_count == scenario.expected_reuse_wave_count,
          scenario.expected_reuse_wave_count,
          actual_wave_count,
          options or {}
        )
      end

      if scenario_name == "wall-covered-flank"
        or scenario_name == "mixed-turret-breach" then
        local first_open_event = find_first_event("breach_progress_updated", function(event)
          return (event.breach_open_segments or 0) > 0
        end)
        local stop_tick = first_open_event and first_open_event.tick or math.huge
        local coverage_violation = find_first_event("coverage_violation", function(event)
          return (event.tick or 0) < stop_tick
        end)
        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "no-coverage-before-breach",
          "outcome",
          coverage_violation == nil,
          true,
          coverage_violation == nil,
          {
            coverage_violation = coverage_violation,
            stop_tick = stop_tick
          }
        )
      end

      if scenario_name == "spitter-siege" then
        local support_mode_event = find_first_event("support_mode_selected")
        local pressure_event = support_mode_event and find_first_event("breach_pressure_detected", function(event)
          return (event.tick or 0) >= support_mode_event.tick and (event.tick or 0) <= support_mode_event.tick + STALL_TIMEOUT_TICKS
        end) or nil
        local stalled_event = find_first_event("state_stalled", function(event)
          return event.reason == "support-resetting" or event.reason == "support-moving" or event.reason == "support-sieging"
        end)
        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "support-progress-within-threshold",
          "outcome",
          support_mode_event ~= nil and pressure_event ~= nil and stalled_event == nil,
          true,
          pressure_event ~= nil,
          {
            support_mode_selected = support_mode_event,
            breach_pressure_detected = pressure_event,
            state_stalled = stalled_event,
            threshold_ticks = STALL_TIMEOUT_TICKS
          }
        )
      end

      if scenario_name == "mixed-breach-siege" then
        local breach_assault_event = find_first_event("breach_assault_planned")
        local breach_group_id = breach_assault_event and breach_assault_event.group_id or nil
        local first_turret_target = breach_assault_event and (
          find_first_event("interior_target_selected", function(event)
            return (event.tick or 0) >= breach_assault_event.tick
              and (not breach_group_id or event.group_id == breach_group_id)
              and event.reason == "combat-turret"
          end)
          or find_first_event("turret_priority_selected", function(event)
            return (event.tick or 0) >= breach_assault_event.tick
              and (not breach_group_id or event.group_id == breach_group_id)
          end)
        ) or nil
        local first_wall_target = breach_assault_event and find_first_event("wall_target_after_breach", function(event)
          return (event.tick or 0) >= breach_assault_event.tick
            and (not breach_group_id or event.group_id == breach_group_id)
        end) or nil

        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "turret-targeted-after-breach",
          "outcome",
          breach_assault_event ~= nil and first_turret_target ~= nil,
          true,
          first_turret_target ~= nil,
          {
            breach_assault_planned = breach_assault_event,
            first_turret_target = first_turret_target
          }
        )

        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "no-wall-target-after-breach",
          "outcome",
          breach_assault_event ~= nil and first_wall_target == nil,
          true,
          first_wall_target == nil,
          {
            breach_assault_planned = breach_assault_event,
            wall_target_after_breach = first_wall_target
          }
        )
      end

      if scenario_name == "breach-reuse" then
        local entered_event = find_first_event("entry_progress_updated", function(event)
          return event.reason == "inside"
        end)
        local interior_target_event = find_first_event("interior_target_selected")
        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "reuse-entered-before-interior-target",
          "outcome",
          entered_event ~= nil
            and interior_target_event ~= nil
            and (entered_event.tick or 0) <= (interior_target_event.tick or math.huge),
          true,
          interior_target_event ~= nil,
          {
            entry_progress_updated = entered_event,
            interior_target_selected = interior_target_event
          }
        )
      end

      if scenario_name == "flame-turret-breach" then
        local cone_violation = find_first_event("coverage_violation", function(event)
          return event.support_mode == "cone-siege"
        end)
        local active_cone_coverage = false
        for _, record in pairs(storage.group_ai) do
          if record.scenario == scenario_name and record.support_mode == "cone-siege" then
            local group = get_group(record)
            if group and #find_covering_turrets(group.surface, group.force, group.position) > 0 then
              active_cone_coverage = true
              break
            end
          end
        end
        assertions[#assertions + 1] = runtime_ext.make_bridge_assertion(
          "cone-outside-flame-range",
          "outcome",
          cone_violation == nil and not active_cone_coverage,
          true,
          cone_violation == nil and not active_cone_coverage,
          {
            coverage_violation = cone_violation,
            active_cone_coverage = active_cone_coverage
          }
        )
      end
    end

    return assertions
  end,
  reset_scenario = function()
    ensure_globals()

    if storage.debug and storage.debug.arena and storage.debug.arena.surface_name and game.surfaces[storage.debug.arena.surface_name] then
      local surface = game.surfaces[storage.debug.arena.surface_name]
      purge_surface_runtime_state(surface.index)
      arena_runtime.clear_debug_surface(surface)
    end

    clear_debug_runtime()
    storage.debug.arena = nil
    set_debug_enabled(0, false)

    return {
      reset = true
    }
  end
})
end

do
runtime_ext.on_group_created = function(event)
  ensure_globals()
  local scenario
  if event.group and event.group.valid and event.group.surface.name == DEBUG_ARENA_SURFACE_NAME and storage.debug.arena then
    scenario = storage.debug.arena.scenario
  end
  local existing = event.group and storage.group_ai[event.group.unique_id] or nil
  register_group(event.group, existing and existing.role or "main", existing and existing.parent_id or nil, scenario)
end

runtime_ext.on_group_finished = function(event)
  ensure_globals()
  local scenario
  if event.group and event.group.valid and event.group.surface.name == DEBUG_ARENA_SURFACE_NAME and storage.debug.arena then
    scenario = storage.debug.arena.scenario
  end
  local existing = event.group and storage.group_ai[event.group.unique_id] or nil
  register_group(event.group, existing and existing.role or "main", existing and existing.parent_id or nil, scenario)
end

runtime_ext.on_ai_command_completed = function(event)
  ensure_globals()
  local record = storage.group_ai[event.unit_number]
  if record then
    mark_command_complete(record, event.result, event.tick or game.tick)
  end
end

runtime_ext.on_entity_damaged = function(event)
  ensure_globals()
  local entity = event.entity
  if not (entity and entity.valid and event.force and event.force.valid and event.force.name == "enemy") then
    return
  end

  if entity.type ~= "wall" and entity.type ~= "gate" then
    return
  end

  local segment_key = position_key(entity.position)
  for _, site in pairs(storage.siege_sites) do
    if site.surface_index == entity.surface.index and site.breach_positions then
      for index = 1, #site.breach_positions do
        if position_key(site.breach_positions[index]) == segment_key then
          local previous_tick = site.last_breach_pressure_tick or 0
          site.last_breach_pressure_tick = event.tick or game.tick
          if previous_tick == 0 or previous_tick + BREACH_PRESSURE_EVENT_COOLDOWN <= site.last_breach_pressure_tick then
            local debug_record
            for _, record in pairs(storage.group_ai) do
              if record.siege_site_id == site.key then
                note_meaningful_progress(record)
                debug_record = record
              end
            end
            record_debug_event("breach_pressure_detected", debug_record, {
              reason = "breach-segment-hit",
              target_position = entity.position,
              siege_site_id = site.key,
              entry_open = site.entry_open,
              support_mode = site.support_mode
            })
          end
          break
        end
      end
    end
  end
end

script.on_event(defines.events.on_unit_group_created, runtime_ext.on_group_created)
script.on_event(defines.events.on_unit_group_finished_gathering, runtime_ext.on_group_finished)
script.on_event(defines.events.on_ai_command_completed, runtime_ext.on_ai_command_completed)
script.on_event(defines.events.on_entity_damaged, runtime_ext.on_entity_damaged)
end

script.on_init(repair_runtime_state)
script.on_configuration_changed(repair_runtime_state)
