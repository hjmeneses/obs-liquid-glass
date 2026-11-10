--[[
  liquid-glass-presets.lua — presets con botones para los filtros Liquid Glass de OBS.

  Por qué un script y no presets dentro del shader: un shader de obs-shaderfilter no puede
  mover sus propios sliders. Si el preset viviera en el shader, ignoraría los sliders y no
  podrías partir de un preset y retocarlo. Este script escribe los valores en la configuración
  del filtro, así que los sliders quedan con los valores del preset y se pueden ajustar después.

  Uso: Herramientas → Scripts → "+" → elige este archivo. Elige el filtro en la lista y
  presiona un preset. Si tenías abierta la ventana de propiedades del filtro, ciérrala y vuelve
  a abrirla para ver los sliders actualizados.
]]

obs = obslua

local SHADER_FILTER_ID = "shader_filter"   -- id del filtro "User-defined shader" (obs-shaderfilter)

-- Parámetros que tocan los presets (mismos nombres en los dos shaders).
-- La posición y el tamaño del panel no se tocan: dependen de tu escena, no del estilo.
local KEYS = {
    "blur_radius", "refraction", "bezel", "bezel_profile", "dispersion", "saturation",
    "tint_amount", "tint_edge", "highlight", "light_angle", "light_speed", "back_light",
    "shadow_opacity", "shadow_size", "liquid_wave", "frost_amount",
}
-- Los colores float4 de obs-shaderfilter se guardan como entero 0xAABBGGRR, no como double
local COLOR_KEYS = { "tint_color" }

local WHITE = 0xFFFFFFFF
local BLACK = 0xFF000000

-- Valores sacados de capturas de iOS 26. Los anchos de bisel están pensados para elementos
-- de 100–400 px a 1080p; si tu forma es mucho más grande, sube "Ancho del bisel".
local PRESETS = {
    {
        id = "control",
        label = "Control (botones del Centro de control)",
        -- Casi sin tinte, fondo muy desenfocado, bisel fino con brillo en dos lados opuestos
        values = {
            blur_radius = 25, refraction = 35, bezel = 12, bezel_profile = 1.0, dispersion = 0.04,
            saturation = 1.4, tint_amount = 0.08, tint_edge = 0.5, highlight = 0.9,
            light_angle = 135, light_speed = 0, back_light = 0.75,
            shadow_opacity = 0.0, shadow_size = 20, liquid_wave = 0, frost_amount = 0,
        },
        colors = { tint_color = WHITE },
    },
    {
        id = "barra",
        label = "Barra oscura (búsqueda / Siri)",
        -- Centro casi negro; el tinte desaparece en el bisel para que se vea el fondo refractado.
        -- Luz desde abajo (270°) porque en iOS el filo brillante está en el borde inferior.
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
        label = "Panel grande (carpeta)",
        -- Desenfoque fuerte para que el contenido de encima se lea, tinte oscuro ligero, bisel muy fino
        values = {
            blur_radius = 35, refraction = 50, bezel = 16, bezel_profile = 1.0, dispersion = 0.05,
            saturation = 1.5, tint_amount = 0.2, tint_edge = 0.6, highlight = 0.6,
            light_angle = 135, light_speed = 0, back_light = 0.7,
            shadow_opacity = 0.1, shadow_size = 30, liquid_wave = 0, frost_amount = 0,
        },
        colors = { tint_color = BLACK },
    },
}

local g_settings = nil       -- configuración del script (aquí se guardan los presets propios)
local g_target = ""          -- "fuente\tfiltro" elegido en la lista
local g_first_target = ""    -- respaldo: el primer filtro encontrado, por si la lista no se ha tocado
local g_preset_name = ""
local g_saved_choice = ""

local function log(msg)
    obs.script_log(obs.LOG_INFO, msg)
end

---------------------------------------------------------------------------
-- Búsqueda de filtros Liquid Glass
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
                local kind = file:find("forma") and "  (forma)" or "  (panel)"
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

    -- obs_enum_sources da fuentes y grupos; las escenas hay que pedirlas aparte
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

-- Ejecuta fn(filtro) sobre el filtro elegido y libera las referencias al terminar
local function with_filter(fn)
    local target = (g_target ~= nil and g_target ~= "") and g_target or g_first_target
    local sname, fname = target:match("^(.-)\t(.*)$")
    if sname == nil then
        log("No hay filtro Liquid Glass elegido. Presiona 'Actualizar lista'.")
        return false
    end
    local src = obs.obs_get_source_by_name(sname)
    if src == nil then
        log("No encontré la fuente '" .. sname .. "'.")
        return false
    end
    local filter = obs.obs_source_get_filter_by_name(src, fname)
    obs.obs_source_release(src)
    if filter == nil then
        log("No encontré el filtro '" .. fname .. "' en '" .. sname .. "'.")
        return false
    end
    fn(filter)
    obs.obs_source_release(filter)
    return true
end

---------------------------------------------------------------------------
-- Aplicar / leer valores
---------------------------------------------------------------------------

-- Primero borra todas las claves del preset (vuelven al valor por defecto del shader) y luego
-- escribe las del preset. Así un preset da siempre el mismo resultado, sin importar qué
-- valores tenía el filtro antes.
local function apply_to_filter(filter, values, colors)
    local s = obs.obs_source_get_settings(filter)
    for _, k in ipairs(KEYS) do obs.obs_data_erase(s, k) end
    for _, k in ipairs(COLOR_KEYS) do obs.obs_data_erase(s, k) end
    for k, v in pairs(values or {}) do obs.obs_data_set_double(s, k, v) end
    for k, v in pairs(colors or {}) do obs.obs_data_set_int(s, k, v) end
    obs.obs_data_release(s)

    -- obs_source_update con datos vacíos fuerza al filtro a releer su configuración
    local empty = obs.obs_data_create()
    obs.obs_source_update(filter, empty)
    obs.obs_data_release(empty)
end

-- Solo guarda claves con valor propio o por defecto conocido; si no, get_double daría 0
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
-- Presets propios (guardados en la configuración del script)
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
        if idx >= 0 then obs.obs_data_array_erase(arr, idx) end   -- mismo nombre = reemplazar

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
        log("Preset guardado: " .. name)
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
        log("Preset borrado: " .. name)
    end
    obs.obs_data_array_release(arr)
end

---------------------------------------------------------------------------
-- Interfaz del script
---------------------------------------------------------------------------

function script_description()
    return [[<h3>Liquid Glass — presets</h3>
<p>Aplica estilos tipo iOS a los filtros <b>Liquid Glass</b> (obs-shaderfilter) con un clic.
Los sliders del filtro quedan con los valores del preset, así que puedes ajustarlos después.</p>
<p>Si tenías abiertas las propiedades del filtro, ciérralas y vuelve a abrirlas para ver los cambios.</p>]]
end

function script_properties()
    local props = obs.obs_properties_create()

    local list = obs.obs_properties_add_list(props, "target", "Filtro de vidrio",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    fill_targets(list)
    obs.obs_properties_add_button(props, "refresh", "Actualizar lista", function(p, _)
        fill_targets(obs.obs_properties_get(p, "target"))
        fill_saved(obs.obs_properties_get(p, "saved"))
        return true
    end)

    for _, preset in ipairs(PRESETS) do
        obs.obs_properties_add_button(props, "preset_" .. preset.id, preset.label, function(_, _)
            if with_filter(function(f) apply_to_filter(f, preset.values, preset.colors) end) then
                log("Preset aplicado: " .. preset.label)
            end
            return false
        end)
    end
    obs.obs_properties_add_button(props, "preset_default", "Valores originales del shader", function(_, _)
        with_filter(function(f) apply_to_filter(f, {}, {}) end)
        return false
    end)

    obs.obs_properties_add_text(props, "preset_name", "Nombre del preset propio", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_button(props, "save", "Guardar valores actuales", function(p, _)
        if g_preset_name == nil or g_preset_name == "" then
            log("Escribe un nombre para el preset antes de guardar.")
            return false
        end
        save_current(g_preset_name)
        fill_saved(obs.obs_properties_get(p, "saved"))
        return true
    end)

    local saved = obs.obs_properties_add_list(props, "saved", "Presets guardados",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    fill_saved(saved)
    obs.obs_properties_add_button(props, "apply_saved", "Aplicar preset guardado", function(_, _)
        if g_saved_choice == nil or g_saved_choice == "" then return false end
        local values, colors = load_saved(g_saved_choice)
        if values ~= nil then
            with_filter(function(f) apply_to_filter(f, values, colors) end)
            log("Preset aplicado: " .. g_saved_choice)
        end
        return false
    end)
    obs.obs_properties_add_button(props, "delete_saved", "Borrar preset guardado", function(p, _)
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
    -- OBS mantiene viva esta referencia mientras el script está cargado; aquí se guardan
    -- los presets propios y OBS los persiste junto con la colección de escenas.
    g_settings = settings
end
