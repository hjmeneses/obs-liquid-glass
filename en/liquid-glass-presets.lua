--[[
  liquid-glass-presets.lua — one-click presets for the Liquid Glass filters in OBS.

  Why a script and not presets inside the shader: an obs-shaderfilter shader can't move its own
  sliders. If the preset lived in the shader it would have to ignore the sliders, and you
  couldn't start from a preset and tweak it. This script writes the values into the filter's
  settings, so the sliders take the preset values and stay adjustable afterwards.

  Usage: Tools → Scripts → "+" → pick this file. Choose the filter in the list and click a
  preset. If the filter's properties window was open, close it and reopen it to see the
  updated sliders.

  Works with both the English (en/) and Spanish shaders: parameter names are identical.
]]

obs = obslua

local SHADER_FILTER_ID = "shader_filter"   -- id of the "User-defined shader" filter (obs-shaderfilter)

-- Parameters the presets touch (same names in both shaders and both languages).
-- Panel position and size are left alone: they depend on your scene, not on the style.
local KEYS = {
    "blur_radius", "refraction", "bezel", "bezel_profile", "dispersion", "saturation",
    "tint_amount", "tint_edge", "highlight", "light_angle", "light_speed", "back_light",
    "shadow_opacity", "shadow_size", "liquid_wave", "frost_amount",
}
-- obs-shaderfilter stores float4 colors as a 0xAABBGGRR integer, not as a double
local COLOR_KEYS = { "tint_color" }

local WHITE = 0xFFFFFFFF
local BLACK = 0xFF000000

-- Values taken from iOS 26 screenshots. Bezel widths assume 100–400 px elements at 1080p
-- (except "Large object"); if your shape is much bigger, raise "Bezel width".
local PRESETS = {
    {
        id = "control",
        label = "Control (Control Center buttons)",
        -- Almost no tint, heavily blurred background, thin bezel with highlight on two opposite sides
        values = {
            blur_radius = 25, refraction = 35, bezel = 12, bezel_profile = 1.0, dispersion = 0.04,
            saturation = 1.4, tint_amount = 0.08, tint_edge = 0.5, highlight = 0.9,
            light_angle = 135, light_speed = 0, back_light = 0.75,
            shadow_opacity = 0.0, shadow_size = 20, liquid_wave = 0, frost_amount = 0,
        },
        colors = { tint_color = WHITE },
    },
    {
        id = "bar",
        label = "Dark bar (search / Siri)",
        -- Near-black center; the tint vanishes in the bezel so the refracted background shows.
        -- Light from below (270°) because in iOS the bright edge line sits on the bottom rim.
        values = {
            blur_radius = 6, refraction = 90, bezel = 18, bezel_profile = 1.0, dispersion = 0.06,
            saturation = 1.3, tint_amount = 0.85, tint_edge = 1.0, highlight = 1.0,
            light_angle = 270, light_speed = 0, back_light = 0.3,
            shadow_opacity = 0.15, shadow_size = 20, liquid_wave = 0, frost_amount = 0,
        },
        colors = { tint_color = BLACK },
    },
    {
        id = "panel",
        label = "Large panel (folder)",
        -- Strong blur so content on top stays readable, light dark tint, very thin bezel
        values = {
            blur_radius = 35, refraction = 50, bezel = 16, bezel_profile = 1.0, dispersion = 0.05,
            saturation = 1.5, tint_amount = 0.2, tint_edge = 0.6, highlight = 0.6,
            light_angle = 135, light_speed = 0, back_light = 0.7,
            shadow_opacity = 0.1, shadow_size = 30, liquid_wave = 0, frost_amount = 0,
        },
        colors = { tint_color = BLACK },
    },
    {
        id = "large",
        label = "Large object (shapes, logos 400 px+)",
        -- Thick decorative piece of glass. Wide bezel so the thickness reads in proportion to the
        -- size. Profile 0.75, not 1: with a wide bezel a fully circular profile crams all the
        -- refraction into a hairline strip and the shape looks like a soap bubble, not glass.
        -- Low dispersion for the same reason (a rainbow rim is what gives the bubble away).
        values = {
            blur_radius = 8, refraction = 110, bezel = 60, bezel_profile = 0.75, dispersion = 0.05,
            saturation = 1.35, tint_amount = 0.05, tint_edge = 0.5, highlight = 1.0,
            light_angle = 135, light_speed = 0, back_light = 0.6,
            shadow_opacity = 0.2, shadow_size = 50, liquid_wave = 0, frost_amount = 0,
        },
        colors = { tint_color = WHITE },
    },
}

local g_settings = nil       -- script settings (user presets are stored here)
local g_target = ""          -- "source\tfilter" chosen in the list
local g_first_target = ""    -- fallback: first filter found, in case the list wasn't touched
local g_preset_name = ""
local g_saved_choice = ""

local function log(msg)
    obs.script_log(obs.LOG_INFO, msg)
end

---------------------------------------------------------------------------
-- Finding Liquid Glass filters
---------------------------------------------------------------------------

local function scan_source(src, list, seen)
    local sname = obs.obs_source_get_name(src)
    if sname == nil or seen[sname] then return end
    seen[sname] = true

    local filters = obs.obs_source_enum_filters(src)
    if filters == nil then return end
    for _, f in ipairs(filters) do
        if obs.obs_source_get_unversioned_id(f) == SHADER_FILTER_ID then
            local fs = obs.obs_source_get_settings(f)
            local file = obs.obs_data_get_string(fs, "shader_file_name") or ""
            obs.obs_data_release(fs)
            if file:find("liquid%-glass") then
                local fname = obs.obs_source_get_name(f)
                -- "shape" = English shader, "forma" = Spanish shader
                local kind = (file:find("shape") or file:find("forma")) and "  (shape)" or "  (panel)"
                local value = sname .. "\t" .. fname
                obs.obs_property_list_add_string(list, sname .. "  →  " .. fname .. kind, value)
                if g_first_target == "" then g_first_target = value end
            end
        end
    end
    obs.source_list_release(filters)
end

local function fill_targets(list)
    obs.obs_property_list_clear(list)
    g_first_target = ""
    local seen = {}

    -- obs_enum_sources returns sources and groups; scenes have to be fetched separately
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, s in ipairs(sources) do scan_source(s, list, seen) end
        obs.source_list_release(sources)
    end
    local scenes = obs.obs_frontend_get_scenes()
    if scenes ~= nil then
        for _, s in ipairs(scenes) do scan_source(s, list, seen) end
        obs.source_list_release(scenes)
    end
end

-- Runs fn(filter) on the chosen filter and releases the references when done
local function with_filter(fn)
    local target = (g_target ~= nil and g_target ~= "") and g_target or g_first_target
    local sname, fname = target:match("^(.-)\t(.*)$")
    if sname == nil then
        log("No Liquid Glass filter selected. Click 'Refresh list'.")
        return false
    end
    local src = obs.obs_get_source_by_name(sname)
    if src == nil then
        log("Source '" .. sname .. "' not found.")
        return false
    end
    local filter = obs.obs_source_get_filter_by_name(src, fname)
    obs.obs_source_release(src)
    if filter == nil then
        log("Filter '" .. fname .. "' not found on '" .. sname .. "'.")
        return false
    end
    fn(filter)
    obs.obs_source_release(filter)
    return true
end

---------------------------------------------------------------------------
-- Applying / reading values
---------------------------------------------------------------------------

-- First erases every preset key (they fall back to the shader default) and then writes the
-- preset's keys. That way a preset always gives the same result regardless of what values
-- the filter had before.
local function apply_to_filter(filter, values, colors)
    local s = obs.obs_source_get_settings(filter)
    for _, k in ipairs(KEYS) do obs.obs_data_erase(s, k) end
    for _, k in ipairs(COLOR_KEYS) do obs.obs_data_erase(s, k) end
    for k, v in pairs(values or {}) do obs.obs_data_set_double(s, k, v) end
    for k, v in pairs(colors or {}) do obs.obs_data_set_int(s, k, v) end
    obs.obs_data_release(s)

    -- obs_source_update with empty data forces the filter to re-read its settings
    local empty = obs.obs_data_create()
    obs.obs_source_update(filter, empty)
    obs.obs_data_release(empty)
end

-- Only stores keys that have their own or a known default value; otherwise get_double returns 0
local function read_from_filter(filter)
    local s = obs.obs_source_get_settings(filter)
    local values, colors = {}, {}
    for _, k in ipairs(KEYS) do
        if obs.obs_data_has_user_value(s, k) or obs.obs_data_has_default_value(s, k) then
            values[k] = obs.obs_data_get_double(s, k)
        end
    end
    for _, k in ipairs(COLOR_KEYS) do
        if obs.obs_data_has_user_value(s, k) or obs.obs_data_has_default_value(s, k) then
            colors[k] = obs.obs_data_get_int(s, k)
        end
    end
    obs.obs_data_release(s)
    return values, colors
end

---------------------------------------------------------------------------
-- User presets (stored in the script settings)
---------------------------------------------------------------------------

local function get_saved_array()
    if g_settings == nil then return nil end
    local arr = obs.obs_data_get_array(g_settings, "saved_presets")
    if arr == nil then arr = obs.obs_data_array_create() end
    return arr
end

local function fill_saved(list)
    obs.obs_property_list_clear(list)
    local arr = get_saved_array()
    if arr == nil then return end
    for i = 0, obs.obs_data_array_count(arr) - 1 do
        local it = obs.obs_data_array_item(arr, i)
        local n = obs.obs_data_get_string(it, "name")
        obs.obs_property_list_add_string(list, n, n)
        obs.obs_data_release(it)
    end
    obs.obs_data_array_release(arr)
end

local function find_saved_index(arr, name)
    for i = 0, obs.obs_data_array_count(arr) - 1 do
        local it = obs.obs_data_array_item(arr, i)
        local n = obs.obs_data_get_string(it, "name")
        obs.obs_data_release(it)
        if n == name then return i end
    end
    return -1
end

local function save_current(name)
    with_filter(function(filter)
        local values, colors = read_from_filter(filter)
        local arr = get_saved_array()

        local idx = find_saved_index(arr, name)
        if idx >= 0 then obs.obs_data_array_erase(arr, idx) end   -- same name = replace

        local item = obs.obs_data_create()
        obs.obs_data_set_string(item, "name", name)
        local v = obs.obs_data_create()
        for k, x in pairs(values) do obs.obs_data_set_double(v, k, x) end
        local c = obs.obs_data_create()
        for k, x in pairs(colors) do obs.obs_data_set_int(c, k, x) end
        obs.obs_data_set_obj(item, "values", v)
        obs.obs_data_set_obj(item, "colors", c)
        obs.obs_data_release(v)
        obs.obs_data_release(c)
        obs.obs_data_array_push_back(arr, item)
        obs.obs_data_release(item)

        obs.obs_data_set_array(g_settings, "saved_presets", arr)
        obs.obs_data_array_release(arr)
        log("Preset saved: " .. name)
    end)
end

local function load_saved(name)
    local arr = get_saved_array()
    if arr == nil then return nil end
    local idx = find_saved_index(arr, name)
    if idx < 0 then
        obs.obs_data_array_release(arr)
        return nil
    end
    local it = obs.obs_data_array_item(arr, idx)
    local v = obs.obs_data_get_obj(it, "values")
    local c = obs.obs_data_get_obj(it, "colors")
    local values, colors = {}, {}
    for _, k in ipairs(KEYS) do
        if obs.obs_data_has_user_value(v, k) then values[k] = obs.obs_data_get_double(v, k) end
    end
    for _, k in ipairs(COLOR_KEYS) do
        if obs.obs_data_has_user_value(c, k) then colors[k] = obs.obs_data_get_int(c, k) end
    end
    obs.obs_data_release(v)
    obs.obs_data_release(c)
    obs.obs_data_release(it)
    obs.obs_data_array_release(arr)
    return values, colors
end

local function delete_saved(name)
    local arr = get_saved_array()
    if arr == nil then return end
    local idx = find_saved_index(arr, name)
    if idx >= 0 then
        obs.obs_data_array_erase(arr, idx)
        obs.obs_data_set_array(g_settings, "saved_presets", arr)
        log("Preset deleted: " .. name)
    end
    obs.obs_data_array_release(arr)
end

---------------------------------------------------------------------------
-- Script UI
---------------------------------------------------------------------------

function script_description()
    return [[<h3>Liquid Glass — presets</h3>
<p>Apply iOS-style looks to <b>Liquid Glass</b> filters (obs-shaderfilter) in one click.
The filter's sliders take the preset values, so you can fine-tune them afterwards.</p>
<p>If the filter's properties window was open, close and reopen it to see the changes.</p>]]
end

function script_properties()
    local props = obs.obs_properties_create()

    local list = obs.obs_properties_add_list(props, "target", "Glass filter",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    fill_targets(list)
    obs.obs_properties_add_button(props, "refresh", "Refresh list", function(p, _)
        fill_targets(obs.obs_properties_get(p, "target"))
        fill_saved(obs.obs_properties_get(p, "saved"))
        return true
    end)

    for _, preset in ipairs(PRESETS) do
        obs.obs_properties_add_button(props, "preset_" .. preset.id, preset.label, function(_, _)
            if with_filter(function(f) apply_to_filter(f, preset.values, preset.colors) end) then
                log("Preset applied: " .. preset.label)
            end
            return false
        end)
    end
    obs.obs_properties_add_button(props, "preset_default", "Shader defaults", function(_, _)
        with_filter(function(f) apply_to_filter(f, {}, {}) end)
        return false
    end)

    obs.obs_properties_add_text(props, "preset_name", "Custom preset name", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(props, "save", "Save current values", function(p, _)
        if g_preset_name == nil or g_preset_name == "" then
            log("Type a preset name before saving.")
            return false
        end
        save_current(g_preset_name)
        fill_saved(obs.obs_properties_get(p, "saved"))
        return true
    end)

    local saved = obs.obs_properties_add_list(props, "saved", "Saved presets",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    fill_saved(saved)
    obs.obs_properties_add_button(props, "apply_saved", "Apply saved preset", function(_, _)
        if g_saved_choice == nil or g_saved_choice == "" then return false end
        local values, colors = load_saved(g_saved_choice)
        if values ~= nil then
            with_filter(function(f) apply_to_filter(f, values, colors) end)
            log("Preset applied: " .. g_saved_choice)
        end
        return false
    end)
    obs.obs_properties_add_button(props, "delete_saved", "Delete saved preset", function(p, _)
        if g_saved_choice == nil or g_saved_choice == "" then return false end
        delete_saved(g_saved_choice)
        fill_saved(obs.obs_properties_get(p, "saved"))
        return true
    end)

    return props
end

function script_update(settings)
    g_target = obs.obs_data_get_string(settings, "target")
    g_preset_name = obs.obs_data_get_string(settings, "preset_name")
    g_saved_choice = obs.obs_data_get_string(settings, "saved")
end

function script_load(settings)
    -- OBS keeps this reference alive while the script is loaded; user presets are stored here
    -- and OBS persists them along with the scene collection.
    g_settings = settings
end
