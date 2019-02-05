-- Script Manager by ShadyRetard

local SCRIPT_FILE_NAME = GetScriptName();
local SCRIPT_FILE_ADDR = "https://raw.githubusercontent.com/hyperthegreat/aw_script_store/master/scriptstore.lua";
local VERSION_FILE_ADDR = "https://raw.githubusercontent.com/hyperthegreat/aw_script_store/master/version.txt";
local VERSION_NUMBER = "1.0.1";
local API_URL = "http://api.shadyretard.io";

local available_scripts = {};
local should_check_available_scripts = true;

local SCRIPTSTORE_WINDOW_X, SCRIPTSTORE_WINDOW_Y = 200, 200;
local SCRIPTSTORE_WINDOW_WIDTH, SCRIPTSTORE_WINDOW_HEIGHT = 900, 460;
local SCRIPTSTORE_CONFIG_WINDOW_WIDTH, SCRIPTSTORE_CONFIG_WINDOW_HEIGHT = 200, 500;
local SCRIPTSTORE_CONFIG_WINDOW_X, SCRIPTSTORE_CONFIG_WINDOW_Y = 400, 400;

local BLOCK_WIDTH, BLOCK_HEIGHT = 200, 200;
local BLOCK_MARGIN = 20;

local TOKEN_COOLDOWN = 5;
local CLICK_COOLDOWN = 1;

local is_dragging = false;
local is_resizing = false;

local last_click = globals.RealTime();
local last_token_update = globals.RealTime();
local dragging_offset_x, dragging_offset_y;

local loaded_config = false;
local token = "";
local configs = {};
local current_config = "default";
local current_page = 1;
local current_sorting = 1;
local sorting_options = {"downloads", "date", "title", "author"};
local current_sorting_direction = 1;

local ref = gui.Reference("SETTINGS", "Lua Scripts");
local SHOW_SCRIPTSTORE_CB = gui.Checkbox(ref, "SHOW_SCRIPTSTORE_CB", "Show Script Manager", false);
gui.Text(ref, "Script Manager Authentication Token")
local SCRIPTSTORE_TOKEN = gui.Editbox(ref, "SCRIPTSTORE_TOKEN", "");

local MAIN_FONT = draw.CreateFont("Tahoma", 13, 13);
local STATUS_FONT = draw.CreateFont("Tahoma Bold", 15, 15);
local ERROR_FONT = draw.CreateFont("Tahoma Bold", 17, 17);

local scriptstore_settings_file = file.Open("scriptstore_settings.dat", "a");
if (scriptstore_settings_file ~= nil) then
    scriptstore_settings_file:Close();
end

local update_available = false;
local version_check_done = false;
local update_downloaded = false;

local animations = {};

function IsMouseInRect(left, top, width, height)
    local mouse_x, mouse_y = input.GetMousePos();
    return (mouse_x >= left and mouse_x <= left + width and mouse_y >= top and mouse_y <= top + height);
end

function IsSameColor(c1, c2)
    return c1[1] == c2[1] and c1[2] == c2[2] and c1[3] == c2[3] and c1[4] == c2[4];
end

function Lerp(a, b, u)
    return (1 - u) * a + u * b;
end

local function UpdateEventHandler()
    if (update_available and not update_downloaded) then
        if (gui.GetValue("lua_allow_cfg") == false) then
            draw.Color(255, 0, 0, 255);
            draw.Text(0, 0, "[SCRIPT MANAGER] An update is available, please enable 'Allow script/config editing from lua' in the settings tab");
        else
            local new_version_content = http.Get(SCRIPT_FILE_ADDR);
            local old_script = file.Open(SCRIPT_FILE_NAME, "w");
            old_script:Write(new_version_content);
            old_script:Close();
            update_available = false;
            update_downloaded = true;
        end
    end

    if (update_downloaded) then
        draw.Color(255, 0, 0, 255);
        draw.Text(0, 0, "[SCRIPT MANAGER] An update has automatically been downloaded, please reload the Script Manager");
        return;
    end

    if (not version_check_done) then
        if (gui.GetValue("lua_allow_http") == false) then
            draw.Color(255, 0, 0, 255);
            draw.Text(0, 0, "[SCRIPT MANAGER] Please enable 'Allow internet connections from lua' in your settings tab to use this script");
            return;
        end

        version_check_done = true;
        local version = http.Get(VERSION_FILE_ADDR);
        if (version ~= VERSION_NUMBER) then
            update_available = true;
        end
    end
end


local function SaveConfig()
    local current_data;
    local scriptstore_settings_file = file.Open("scriptstore_settings.dat", "r");
    if (scriptstore_settings_file == nil) then
        return;
    end

    local contents = scriptstore_settings_file:Read();
    scriptstore_settings_file:Close();

    if (contents ~= '') then
        current_data = json.decode(contents);
    end

    local settings = {};
    settings.configs = configs;

    if (current_data ~= nil and current_data.configs ~= nil) then
        settings.configs = current_data.configs;
        settings.configs[current_config] = configs[current_config];
    end

    settings.sorting = current_sorting;
    settings.token = token;
    local scriptstore_settings_file = file.Open("scriptstore_settings.dat", "w");
    scriptstore_settings_file:Write(json.encode(settings));
    scriptstore_settings_file:Close();
end


local function ActivateScript(script, do_save)
    http.Get(API_URL .. "/scripts/code/" .. script._id .. "?token=" .. token, function(script_code)
        if (script_code == nil or script_code == "error") then
            script.error = "NETWORK ERROR";
            return;
        elseif (script_code == "access_denied") then
            script.error = "ACCESS DENIED";
            return;
        end

        local activator = file.Open("scriptstore_activation.lua", "w");
        activator:Write(script_code);
        activator:Close();
        RunScript("scriptstore_activation.lua");

        if (do_save ~= nil or do_save == false) then
            return;
        end

        if (configs[current_config] == nil) then
            configs[current_config] = {
                scripts = {}
            }
        end

        table.insert(configs[current_config].scripts, script);
        file.Delete("scriptstore_activation.lua");
        script.error = nil;
        SaveConfig();
    end);
end

local function DeactivateScript(script)
    local script_deactivation = "";

    for i = 1, #script.callbacks do
        local callback = script.callbacks[i];
        script_deactivation = script_deactivation .. "callbacks.Unregister('" .. callback.id .. "', '" .. callback.uniqueId .. "'); \n";
    end

    if (script_deactivation ~= "") then
        local deactivator = file.Open("scriptstore_deactivation.lua", "w");
        deactivator:Write(script_deactivation);
        deactivator:Close();
        RunScript("scriptstore_deactivation.lua");
        file.Delete("scriptstore_deactivation.lua");
    end

    if (configs[current_config] == nil) then
        configs[current_config] = {
            scripts = {}
        };
    end

    for i = 1, #configs[current_config].scripts do
        if (configs[current_config].scripts[i].id == script.id) then
            table.remove(configs[current_config].scripts, i);
            break;
        end
    end

    SaveConfig();
end

local function LoadSettings()
    local scriptstore_settings_file = file.Open("scriptstore_settings.dat", "r");
    if (scriptstore_settings_file == nil) then
        return;
    end

    local contents = scriptstore_settings_file:Read();
    scriptstore_settings_file:Close();
    if (contents == '') then
        return;
    end

    local settings = json.decode(contents);
    if (settings == nil or settings == "" or settings.configs == nil) then
        return;
    end

    current_sorting = settings.sorting;
    token = settings.token;
    SCRIPTSTORE_TOKEN:SetValue(token);
    configs = settings.configs;

    if (configs == nil or configs["default"] == nil) then
        return;
    end

    for i = 1, #configs["default"].scripts do
        ActivateScript(configs["default"].scripts[i], false);
    end
end

local function IsActiveScript(script)
    local found = false;
    local update_available = false;
    if (configs[current_config] ~= nil and configs[current_config].scripts ~= nil) then
        for i = 1, #configs[current_config].scripts do
            if (configs[current_config].scripts[i].id == script.id) then
                found = true;
                if (configs[current_config].scripts[i].__v ~= script.__v) then
                    update_available = true;
                end

                break
            end
        end
    end
    return found, update_available;
end

local function ChangeConfig(config_name)
    if (config_name == current_config) then
        return;
    end

    local should_be_deactivated = {};
    for i = 1, #configs[current_config].scripts do
        local script = configs[current_config].scripts[i];
        should_be_deactivated[script.id] = script;
    end

    local should_be_activated = {};

    local new_config = configs[config_name];
    for i = 1, new_config.scripts do
        local script = new_config.scripts[i];
        local is_active = IsActiveScript(script);
        if (is_active) then
            should_be_deactivated[script.id] = nil;
        else
            table.insert(should_be_activated, script);
        end
    end

    current_config = config_name;

    -- Deactivate old scripts
    for index, obj in pairs(should_be_deactivated) do
        if (obj ~= nil) then
            DeactivateScript(obj);
        end
    end

    -- Activate new scripts
    for i = 1, #should_be_activated do
        local script = should_be_activated[i];
        if script ~= nil then
            ActivateScript(script);
        end
    end
end

local function GetScriptStoreData()
    local scriptstore_data = http.Get(API_URL .. "/scripts?sort=" .. sorting_options[current_sorting] .. "&direction=" .. current_sorting_direction .. "&token=" .. token);
    if (scriptstore_data == nil or scriptstore_data == "error") then
        return;
    end

    available_scripts = json.decode(scriptstore_data);

    for i = 1, #available_scripts do
        http.Get(API_URL .. "/scripts/image/" .. available_scripts[i]._id .. "?token=" .. token, function(image_data)
            if (image_data == nil or image_data == "error") then
                available_scripts[i].error = "NETWORK ERROR";
            elseif (image_data == "access_denied") then
                available_scripts[i].error = "ACCESS DENIED";
            else
                available_scripts[i].image = draw.CreateTexture(common.DecodePNG(image_data));
            end
        end);
    end
end

local function HandleMouseEvent()
    if (gui.GetValue("lua_allow_http") == false) then
        return;
    end

    local mouse_x, mouse_y = input.GetMousePos();
    local left_mouse_down = input.IsButtonDown(1);
    local left_mouse_pressed = input.IsButtonPressed(1);

    if (is_dragging == true and left_mouse_down == false) then
        is_dragging = false;
        dragging_offset_x = 0;
        dragging_offset_y = 0;
        return;
    end

    if (is_resizing == true and left_mouse_down == false) then
        is_resizing = false;
        return;
    end

    if (is_dragging == true) then
        SCRIPTSTORE_WINDOW_X = mouse_x - dragging_offset_x;
        SCRIPTSTORE_WINDOW_Y = mouse_y - dragging_offset_y;
        return;
    end

    if (is_resizing) then
        SCRIPTSTORE_WINDOW_WIDTH = math.max(mouse_x - SCRIPTSTORE_WINDOW_X, (BLOCK_WIDTH + BLOCK_MARGIN * 2) * 2);
        SCRIPTSTORE_WINDOW_HEIGHT = math.max(mouse_y - SCRIPTSTORE_WINDOW_Y - 20, (BLOCK_HEIGHT + BLOCK_MARGIN * 2) * 2);
        return;
    end

    if (left_mouse_pressed and IsMouseInRect(SCRIPTSTORE_WINDOW_X, SCRIPTSTORE_WINDOW_Y - 50, SCRIPTSTORE_WINDOW_WIDTH, 25)) then
        is_dragging = true;
        dragging_offset_x = mouse_x - SCRIPTSTORE_WINDOW_X;
        dragging_offset_y = mouse_y - SCRIPTSTORE_WINDOW_Y;
        return;
    end

    if (left_mouse_pressed and IsMouseInRect(SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH - 5, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT + 5, 25, 25)) then
        is_resizing = true;
        return;
    end
end

local function DrawMenuButtons(mouse_down)
    local buttons = {};

--    table.insert(buttons, {
--        text = "Configs",
--        click = function()
--
--        end
--    })

    table.insert(buttons, {
        text = "Refresh",
        click = function()
            should_check_available_scripts = true;
        end
    });

    local text = "ASC";
    if (current_sorting_direction == 1) then
        text = "DESC";
    end

    table.insert(buttons, {
        text = text,
        click = function ()
            if (current_sorting_direction == 1) then
                current_sorting_direction = 0;
            else
                current_sorting_direction = 1;
            end
            should_check_available_scripts = true;
        end
    });

    table.insert(buttons, {
        text = "Sort by " .. sorting_options[current_sorting],
        click = function()
            if (current_sorting < #sorting_options) then
                current_sorting = current_sorting + 1;
            else
                current_sorting = 1;
            end
            should_check_available_scripts = true;
        end
    });

    local y = SCRIPTSTORE_WINDOW_Y - 50;
    local last_button_x = SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH;
    for i=1, #buttons do
        local button = buttons[i];
        local animation_id = "MENU_BUTTON_" .. i;
        local text_w, text_h = draw.GetTextSize(button.text);
        if (IsMouseInRect(last_button_x - 16 - text_w, y, 10 + text_w, 25)) then
            AddAnimation(animation_id, "HOVER", { gui.GetValue('clr_gui_window_header_tab1') }, { gui.GetValue('clr_gui_window_header_tab2') }, 10);
            if (not is_dragging and not is_resizing and mouse_down) then
                button.click();
                last_click = globals.RealTime();
            end
        else
            AddAnimation(animation_id, "NONE", { gui.GetValue('clr_gui_window_header_tab1') }, { gui.GetValue('clr_gui_window_header_tab1') }, 10);
        end
        DoAnimation(animation_id);
        draw.FilledRect(last_button_x - 16 - text_w, y, last_button_x, y + 25);
        draw.Color(gui.GetValue('clr_gui_text1'));
        draw.TextShadow(last_button_x - 8 - text_w, y + 25 - 18, button.text);

        last_button_x = last_button_x - 16 - text_w;
    end

end

local function DrawMenu(mouse_down)
    draw.SetFont(MAIN_FONT);
    draw.Color(gui.GetValue('clr_gui_window_background'));
    draw.FilledRect(SCRIPTSTORE_WINDOW_X, SCRIPTSTORE_WINDOW_Y - 25, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT);
    draw.Color(gui.GetValue('clr_gui_window_header'));
    draw.FilledRect(SCRIPTSTORE_WINDOW_X, SCRIPTSTORE_WINDOW_Y - 50, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH, SCRIPTSTORE_WINDOW_Y - 25);
    draw.Color(gui.GetValue('clr_gui_window_header_tab2'));
    draw.FilledRect(SCRIPTSTORE_WINDOW_X, SCRIPTSTORE_WINDOW_Y - 25, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH, SCRIPTSTORE_WINDOW_Y - 25 + 4);
    draw.Color(gui.GetValue('clr_gui_text1'));
    draw.TextShadow(SCRIPTSTORE_WINDOW_X + 8, SCRIPTSTORE_WINDOW_Y - 25 - 18, "Aimware Script Manager");

    DrawMenuButtons(mouse_down);

    draw.Color(gui.GetValue('clr_gui_window_footer'));
    draw.FilledRect(SCRIPTSTORE_WINDOW_X, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT + 20);
    draw.Color(gui.GetValue('clr_gui_window_footer_text'));
    draw.TextShadow(SCRIPTSTORE_WINDOW_X + 8, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT + 4, "By ShadyRetard");
    DrawShadow(SCRIPTSTORE_WINDOW_X, SCRIPTSTORE_WINDOW_Y - 50, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH, SCRIPTSTORE_WINDOW_Y - 25 + SCRIPTSTORE_WINDOW_HEIGHT + 20, 'clr_gui_window_shadow', 20, 2);

    draw.Color(gui.GetValue('clr_gui_controls1'));

    draw.FilledRect(SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH + 5, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT + 14, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH + 9, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT + 30);
    draw.FilledRect(SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH - 5, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT + 26, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH + 9, SCRIPTSTORE_WINDOW_Y + SCRIPTSTORE_WINDOW_HEIGHT + 30);
end

local function DrawScript(page, col, row, script, is_active, is_update_available, mouse_down)
    draw.SetFont(MAIN_FONT);
    local script_x, script_y = BLOCK_MARGIN + SCRIPTSTORE_WINDOW_X + (col * (BLOCK_MARGIN + BLOCK_WIDTH)), BLOCK_MARGIN + SCRIPTSTORE_WINDOW_Y + (row * (BLOCK_MARGIN + BLOCK_HEIGHT));

    if (not is_dragging and not is_resizing and mouse_down and IsMouseInRect(script_x, script_y, BLOCK_WIDTH, BLOCK_HEIGHT)) then
        last_click = globals.RealTime();
        if (is_active == false or script.error ~= nil) then
            ActivateScript(script);
            return false;
        else
            DeactivateScript(script);
            return false;
        end
    end

    draw.Color(gui.GetValue('clr_gui_groupbox_background'));
    draw.FilledRect(script_x, script_y, script_x + BLOCK_WIDTH, script_y + BLOCK_HEIGHT);

    -- Script background
    local animation_id = "script_" .. page .. "-" .. row .. "-" .. col;
    local original_color = { 255, 255, 255, 100 };
    if (is_active and is_update_available) then
        AddAnimation(animation_id, "UPDATE_AVAILABLE", original_color, { 255, 0, 0, 255 }, 10);
    elseif (is_active) then
        AddAnimation(animation_id, "ACTIVE", original_color, { 255, 255, 255, 255 }, 10);
    elseif (IsMouseInRect(script_x, script_y, BLOCK_WIDTH, BLOCK_HEIGHT)) then
        AddAnimation(animation_id, "HOVER", original_color, { 255, 255, 255, 150 }, 10);
    else
        AddAnimation(animation_id, "NONE", original_color, original_color, 10);
    end
    DoAnimation(animation_id);

    if (script.image ~= nil) then
        draw.SetTexture(script.image);
        draw.FilledRect(script_x + 1, script_y + 1, script_x + BLOCK_WIDTH - 1, script_y + BLOCK_HEIGHT - 1);
        draw.SetTexture(nil);
    end

    -- Script title
    local chars_per_line = math.floor(BLOCK_WIDTH / draw.GetTextSize('a'));
    local num_of_lines = math.ceil(string.len(script.title) / chars_per_line);
    for i = 1, num_of_lines do
        draw.Color(0, 0, 0, 80);
        draw.FilledRect(script_x, (i-1) * 25 + script_y, script_x + BLOCK_WIDTH, (i-1) * 25 + script_y + 25);
        draw.Color(gui.GetValue('clr_gui_text1'));
        draw.TextShadow(script_x + 8, (i-1) * 25 + script_y + 8, string.sub(script.title, (i-1) * chars_per_line, i * chars_per_line - 1));
    end

    -- Script author
    draw.Color(0, 0, 0, 80);
    draw.FilledRect(script_x, num_of_lines * 25 + script_y, script_x + BLOCK_WIDTH, num_of_lines * 25 + script_y + 25);
    draw.Color(gui.GetValue('clr_gui_text1'));
    draw.TextShadow(script_x + 8, num_of_lines * 25 + script_y + 8, "By " .. script.author);

    -- Script additional info
    draw.Color(0, 0, 0, 80);
    draw.FilledRect(script_x, script_y + BLOCK_HEIGHT - 25, script_x + BLOCK_WIDTH, script_y + BLOCK_HEIGHT);
    draw.Color(gui.GetValue('clr_gui_text1'));
    draw.TextShadow(script_x + 8, script_y + BLOCK_HEIGHT - 17, script.date .. " | " .. script.downloads .. " uses");

    draw.SetFont(STATUS_FONT);

    -- Active status
    if (script.error) then
        local active_text_w, active_text_h = draw.GetTextSize(script.error);
        draw.Color(255, 0, 0, 255);
        draw.TextShadow(script_x + (BLOCK_WIDTH / 2) - (active_text_w / 2), script_y + (BLOCK_HEIGHT / 2) - (active_text_h / 2), script.error);
    elseif (is_active and is_update_available) then
        local active_text_w, active_text_h = draw.GetTextSize("UPDATE AVAILABLE");
        draw.Color(255, 0, 0, 255);
        draw.TextShadow(script_x + (BLOCK_WIDTH / 2) - (active_text_w / 2), script_y + (BLOCK_HEIGHT / 2) - (active_text_h / 2), "UPDATE AVAILABLE");
    elseif (is_active) then
        local active_text_w, active_text_h = draw.GetTextSize("ACTIVE");
        draw.Color(148, 242, 120, 255);
        draw.TextShadow(script_x + (BLOCK_WIDTH / 2) - (active_text_w / 2), script_y + (BLOCK_HEIGHT / 2) - (active_text_h / 2), "ACTIVE");
    end

    -- Script shadow
    DrawShadow(script_x, script_y, script_x + BLOCK_WIDTH, script_y + BLOCK_HEIGHT, 'clr_gui_groupbox_shadow', 25, 3);

    return true;
end

local function DrawPagination(mouse_down, pages)
    if (current_page == 1) then
        local disabled_color = { gui.GetValue('clr_gui_button_idle') }
        draw.Color(disabled_color[1], disabled_color[2], disabled_color[3], 50);
    elseif (IsMouseInRect(BLOCK_MARGIN + SCRIPTSTORE_WINDOW_X + 8 - 4, SCRIPTSTORE_WINDOW_Y - 25 + 13 - 4, 28, 28)) then
        if (not is_dragging and not is_resizing and mouse_down) then
            if (current_page > pages) then
                current_page = pages;
            else
                current_page = current_page - 1;
            end

            last_click = globals.RealTime();
        end

        draw.Color(gui.GetValue('clr_gui_button_hover'));
    else
        draw.Color(gui.GetValue('clr_gui_button_idle'));
    end
    for i = 1, 4 do
        draw.RoundedRectFill(BLOCK_MARGIN + SCRIPTSTORE_WINDOW_X + 8 - i, SCRIPTSTORE_WINDOW_Y - 25 + 13 - i, BLOCK_MARGIN + SCRIPTSTORE_WINDOW_X + 8 + 20 + i, SCRIPTSTORE_WINDOW_Y + 8 + i);
    end
    draw.Color(gui.GetValue('clr_gui_text1'));
    draw.TextShadow(BLOCK_MARGIN + SCRIPTSTORE_WINDOW_X + 13, SCRIPTSTORE_WINDOW_Y - 9, "<");

    -- TODO: Show page numbers based on available space

    if (current_page >= pages) then
        local disabled_color = { gui.GetValue('clr_gui_button_idle') }
        draw.Color(disabled_color[1], disabled_color[2], disabled_color[3], 50);
    elseif (IsMouseInRect(SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH - BLOCK_MARGIN - 8 - 20 - 4, SCRIPTSTORE_WINDOW_Y - 25 + 13 - 4, 28, 28)) then
        if (not is_dragging and not is_resizing and mouse_down) then
            current_page = current_page + 1;
            last_click = globals.RealTime();
        end

        draw.Color(gui.GetValue('clr_gui_button_hover'));
    else
        draw.Color(gui.GetValue('clr_gui_button_idle'));
    end
    for i = 1, 4 do
        draw.RoundedRectFill(SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH - BLOCK_MARGIN - 8 - 20 - i, SCRIPTSTORE_WINDOW_Y - 25 + 13 - i, SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH - BLOCK_MARGIN - 8 + i, SCRIPTSTORE_WINDOW_Y + 8 + i);
    end
    draw.Color(gui.GetValue('clr_gui_text1'));
    draw.TextShadow(SCRIPTSTORE_WINDOW_X + SCRIPTSTORE_WINDOW_WIDTH - BLOCK_MARGIN - 23, SCRIPTSTORE_WINDOW_Y - 9, ">");
end

local function DrawScripts(mouse_down)
    if (available_scripts == nil or #available_scripts == 0) then
        return;
    end

    local max_scripts_width = math.floor((SCRIPTSTORE_WINDOW_WIDTH - BLOCK_MARGIN) / (BLOCK_WIDTH + (BLOCK_MARGIN)));
    local max_scripts_height = math.floor((SCRIPTSTORE_WINDOW_HEIGHT - BLOCK_MARGIN) / (BLOCK_HEIGHT + (BLOCK_MARGIN)));

    local max_shown_scripts = (max_scripts_width * max_scripts_height);
    local pages = math.ceil(#available_scripts / max_shown_scripts);

    DrawPagination(mouse_down, pages);

    for i = 1, pages do
        if (i == current_page) then
            local row = 1;
            local col = 1;
            local start_index = (i - 1) * max_shown_scripts;

            for y = 1, max_shown_scripts do
                if (y + start_index > #available_scripts) then
                    break;
                end

                row = math.ceil(y / max_scripts_width);
                col = y - ((row - 1) * max_scripts_width);

                local script = available_scripts[y + start_index];

                if (script == nil) then
                    break;
                end

                local is_active, is_update_available = IsActiveScript(script);

                if (DrawScript(i, col - 1, row - 1, script, is_active, is_update_available, mouse_down) == false) then
                    break;
                end
            end
        end
    end
end

local function DrawEvent()
    if (gui.GetValue("lua_allow_http") == false) then
        return;
    end

    draw.SetFont(MAIN_FONT);
    if (draw == nil) then
        return;
    end

    if (last_token_update ~= nil and last_token_update > globals.RealTime()) then
        last_token_update = globals.RealTime();
    end

    if (loaded_config == false) then
        loaded_config = true;
        LoadSettings();
        return;
    end

    if (loaded_config == true and token ~= SCRIPTSTORE_TOKEN:GetValue() and globals.RealTime() - last_token_update > TOKEN_COOLDOWN) then
        token = SCRIPTSTORE_TOKEN:GetValue();
        last_token_update = globals.RealTime();
        SaveConfig();
    end

    if (SHOW_SCRIPTSTORE_CB:GetValue() == false) then
        return;
    end

    if (should_check_available_scripts == true) then
        should_check_available_scripts = false;
        GetScriptStoreData();
        return;
    end

    if (last_click ~= nil and last_click > globals.RealTime()) then
        last_click = globals.RealTime();
    end

    local mouse_down = input.IsButtonPressed(1);
    DrawMenu(mouse_down);
    DrawScripts(mouse_down);
end

function AddAnimation(animation_id, action, start_color, end_color, duration)
    local animation = animations[animation_id];
    local override = false;

    if (animation ~= nil and animation.action ~= action and (IsSameColor(animation.start_color, start_color) == false or IsSameColor(animation.end_color, end_color) == false or animation.duration ~= duration)) then
        start_color = GetColorsByStep(animation);
        override = true;
    end

    if (animation == nil or override) then
        animations[animation_id] = {
            start_color = start_color,
            action = action,
            end_color = end_color,
            duration = duration,
            step = 0
        };
    end
end

function GetColorsByStep(animation)
    local r = math.max(animation.end_color[1], math.min(255, math.ceil(Lerp(animation.start_color[1], animation.end_color[1], animation.step))));
    local g = math.max(animation.end_color[2], math.min(255, math.ceil(Lerp(animation.start_color[2], animation.end_color[2], animation.step))));
    local b = math.max(animation.end_color[3], math.min(255, math.ceil(Lerp(animation.start_color[3], animation.end_color[3], animation.step))));
    local a = math.max(animation.end_color[4], math.min(255, math.ceil(Lerp(animation.start_color[4], animation.end_color[4], animation.step))));
    return { r, g, b, a }
end

function DoAnimation(animation_id)
    local animation = animations[animation_id];
    if (animation == nil or animation.is_active == false) then
        return;
    end

    local colors = GetColorsByStep(animation);
    draw.Color(colors[1], colors[2], colors[3], colors[4]);
    animations[animation_id].step = animation.step + 1.0 / animation.duration;
end

function DrawShadow(left, top, right, bottom, color, length, fade)
    local shadow_r, shadow_g, shadow_b, shadow_a = gui.GetValue(color);

    local a = math.min(shadow_a, length);
    local l = left;
    local t = top;
    local r = right;
    local b = bottom;
    for i = 1, length / 2 do
        a = a - fade;

        if (a < 0) then
            break;
        end

        l = l - 1;
        t = t - 1;
        b = b + 1;
        r = r + 1;
        draw.Color(shadow_r, shadow_g, shadow_b, a);
        draw.OutlinedRect(l, t, r, b);
    end
end

callbacks.Register("Draw", "ScriptManager_DrawEvent", DrawEvent);
callbacks.Register("Draw", "ScriptManager_HandleMouseEvent", HandleMouseEvent);
callbacks.Register("Draw", "ScriptManager_UpdateHandler", UpdateEventHandler);

-- Lightweight JSON Library for Lua
-- Credits: RXI
-- Link / Github: https://github.com/rxi/json.lua/blob/master/json.lua
-- Minified Version
json = { _version = "0.1.1" } local b; local c = { ["\\"] = "\\\\", ["\""] = "\\\"", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" } local d = { ["\\/"] = "/" } for e, f in pairs(c) do d[f] = e end; local function g(h) return c[h] or string.format("\\u%04x", h:byte()) end

; local function i(j) return "null" end

; local function k(j, l) local m = {} l = l or {} if l[j] then error("circular reference") end; l[j] = true; if j[1] ~= nil or next(j) == nil then local n = 0; for e in pairs(j) do if type(e) ~= "number" then error("invalid table: mixed or invalid key types") end; n = n + 1 end; if n ~= #j then error("invalid table: sparse array") end; for o, f in ipairs(j) do table.insert(m, b(f, l)) end; l[j] = nil; return "[" .. table.concat(m, ",") .. "]" else for e, f in pairs(j) do if type(e) ~= "string" then error("invalid table: mixed or invalid key types") end; table.insert(m, b(e, l) .. ":" .. b(f, l)) end; l[j] = nil; return "{" .. table.concat(m, ",") .. "}" end end

; local function p(j) return '"' .. j:gsub('[%z\1-\31\\"]', g) .. '"' end

; local function q(j) if j ~= j or j <= -math.huge or j >= math.huge then error("unexpected number value '" .. tostring(j) .. "'") end; return string.format("%.14g", j) end

; local r = { ["nil"] = i, ["table"] = k, ["string"] = p, ["number"] = q, ["boolean"] = tostring } b = function(j, l) local s = type(j) local t = r[s] if t then return t(j, l) end; error("unexpected type '" .. s .. "'") end; function json.encode(j) return b(j) end

; local u; local function v(...) local m = {} for o = 1, select("#", ...) do m[select(o, ...)] = true end; return m end

; local w = v(" ", "\t", "\r", "\n") local x = v(" ", "\t", "\r", "\n", "]", "}", ",") local y = v("\\", "/", '"', "b", "f", "n", "r", "t", "u") local z = v("true", "false", "null") local A = { ["true"] = true, ["false"] = false, ["null"] = nil } local function B(C, D, E, F) for o = D, #C do if E[C:sub(o, o)] ~= F then return o end end; return #C + 1 end

; local function G(C, D, H) local I = 1; local J = 1; for o = 1, D - 1 do J = J + 1; if C:sub(o, o) == "\n" then I = I + 1; J = 1 end end; error(string.format("%s at line %d col %d", H, I, J)) end

; local function K(n) local t = math.floor; if n <= 0x7f then return string.char(n) elseif n <= 0x7ff then return string.char(t(n / 64) + 192, n % 64 + 128) elseif n <= 0xffff then return string.char(t(n / 4096) + 224, t(n % 4096 / 64) + 128, n % 64 + 128) elseif n <= 0x10ffff then return string.char(t(n / 262144) + 240, t(n % 262144 / 4096) + 128, t(n % 4096 / 64) + 128, n % 64 + 128) end; error(string.format("invalid unicode codepoint '%x'", n)) end

; local function L(M) local N = tonumber(M:sub(3, 6), 16) local O = tonumber(M:sub(9, 12), 16) if O then return K((N - 0xd800) * 0x400 + O - 0xdc00 + 0x10000) else return K(N) end end

; local function P(C, o) local Q = false; local R = false; local S = false; local T; for U = o + 1, #C do local V = C:byte(U) if V < 32 then G(C, U, "control character in string") end; if T == 92 then if V == 117 then local W = C:sub(U + 1, U + 5) if not W:find("%x%x%x%x") then G(C, U, "invalid unicode escape in string") end; if W:find("^[dD][89aAbB]") then R = true else Q = true end else local h = string.char(V) if not y[h] then G(C, U, "invalid escape char '" .. h .. "' in string") end; S = true end; T = nil elseif V == 34 then local M = C:sub(o + 1, U - 1) if R then M = M:gsub("\\u[dD][89aAbB]..\\u....", L) end; if Q then M = M:gsub("\\u....", L) end; if S then M = M:gsub("\\.", d) end; return M, U + 1 else T = V end end; G(C, o, "expected closing quote for string") end

; local function X(C, o) local V = B(C, o, x) local M = C:sub(o, V - 1) local n = tonumber(M) if not n then G(C, o, "invalid number '" .. M .. "'") end; return n, V end

; local function Y(C, o) local V = B(C, o, x) local Z = C:sub(o, V - 1) if not z[Z] then G(C, o, "invalid literal '" .. Z .. "'") end; return A[Z], V end

; local function _(C, o) local m = {} local n = 1; o = o + 1; while 1 do local V; o = B(C, o, w, true) if C:sub(o, o) == "]" then o = o + 1; break end; V, o = u(C, o) m[n] = V; n = n + 1; o = B(C, o, w, true) local a0 = C:sub(o, o) o = o + 1; if a0 == "]" then break end; if a0 ~= "," then G(C, o, "expected ']' or ','") end end; return m, o end

; local function a1(C, o) local m = {} o = o + 1; while 1 do local a2, j; o = B(C, o, w, true) if C:sub(o, o) == "}" then o = o + 1; break end; if C:sub(o, o) ~= '"' then G(C, o, "expected string for key") end; a2, o = u(C, o) o = B(C, o, w, true) if C:sub(o, o) ~= ":" then G(C, o, "expected ':' after key") end; o = B(C, o + 1, w, true) j, o = u(C, o) m[a2] = j; o = B(C, o, w, true) local a0 = C:sub(o, o) o = o + 1; if a0 == "}" then break end; if a0 ~= "," then G(C, o, "expected '}' or ','") end end; return m, o end

; local a3 = { ['"'] = P, ["0"] = X, ["1"] = X, ["2"] = X, ["3"] = X, ["4"] = X, ["5"] = X, ["6"] = X, ["7"] = X, ["8"] = X, ["9"] = X, ["-"] = X, ["t"] = Y, ["f"] = Y, ["n"] = Y, ["["] = _, ["{"] = a1 } u = function(C, D) local a0 = C:sub(D, D) local t = a3[a0] if t then return t(C, D) end; G(C, D, "unexpected character '" .. a0 .. "'") end; function json.decode(C) if type(C) ~= "string" then error("expected argument of type string, got " .. type(C)) end; local m, D = u(C, B(C, 1, w, true)) D = B(C, D, w, true) if D <= #C then G(C, D, "trailing garbage") end; return m end

; return a