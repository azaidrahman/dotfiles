local wezterm = require('wezterm')
local platform = require('utils.platform')
local backdrops = require('utils.backdrops')
local act = wezterm.action
local mux = wezterm.mux

local mod = {}
local mac_keys = {}
local keys = {}

if platform.is_mac then
   mod.SUPER = 'OPT'
   mod.SUPER_REV = 'SUPER|OPT'
   mod.REV_SHIFT = 'CMD|SHIFT'
   -- https://wezterm.org/config/lua/keyassignment/SendKey.html
   mac_keys = {
      -- changing CMD-y to Ctrl-y on nvim
      -- { key = 'SUPER', action = act.SendKey({ key = 'Control', mods = 'CTRL' }) },
      { key = 'y', mods = 'CMD', action = act.SendKey({ key = 'y', mods = 'CTRL' }) },
      { key = 'd', mods = 'CMD', action = act.SendKey({ key = 'd', mods = 'CTRL' }) },
      { key = 'u', mods = 'CMD', action = act.SendKey({ key = 'u', mods = 'CTRL' }) },
      { key = 'c', mods = 'CMD', action = act.SendKey({ key = 'c', mods = 'CTRL' }) },
      { key = 'l', mods = 'CMD', action = act.SendKey({ key = 'l', mods = 'CTRL' }) },
      { key = 'e', mods = 'CMD', action = act.SendKey({ key = 'e', mods = 'CTRL' }) },
      { key = 'o', mods = 'CMD', action = act.SendKey({ key = 'o', mods = 'CTRL' }) },
      { key = 's', mods = 'CMD', action = act.SendKey({ key = 's', mods = 'CTRL' }) },
      { key = 'q', mods = 'CMD', action = act.SendKey({ key = 'q', mods = 'CTRL' }) },
      { key = 'j', mods = 'CMD', action = act.SendKey({ key = 'j', mods = 'CTRL' }) },
      { key = 'k', mods = 'CMD', action = act.SendKey({ key = 'k', mods = 'CTRL' }) },
      -- { key = 'f', mods = 'CMD', action = act.Search { CaseInSensitiveString = '' } },
      -- { key = 'v', mods = 'CMD', action = act.PasteFrom 'Clipboard' },
      -- { key = 'c', mods = 'CMD', action = act.CopyTo 'Clipboard' },
   }
elseif platform.is_win or platform.is_linux then
   mod.SUPER = 'ALT' -- to not conflict with Windows key shortcuts
   mod.SUPER_REV = 'ALT|CTRL'
   mod.REV_SHIFT = 'CTRL|SHIFT'
end

-- stylua: ignore
keys = {
    -- misc/useful --
    { key = 'F1', mods = 'NONE', action = 'ActivateCopyMode' },
    { key = 'F2', mods = 'NONE', action = act.ActivateCommandPalette },
    { key = 'F3', mods = 'NONE', action = act.ShowLauncher },
    { key = 'F4', mods = 'NONE', action = act.ShowLauncherArgs({ flags = 'FUZZY|TABS' }) },
    {
        key = 'F5',
        mods = 'NONE',
        action = act.ShowLauncherArgs({ flags = 'FUZZY|WORKSPACES' }),
    },
    { key = 'F11', mods = 'NONE',    action = act.ToggleFullScreen },
    { key = 'F12', mods = 'NONE',    action = act.ShowDebugOverlay },
    -- { key = 'f',   mods = mod.SUPER, action = act.Search({ CaseInSensitiveString = '' }) },
    {
        key = 'u',
        mods = mod.SUPER_REV,
        action = wezterm.action.QuickSelectArgs({
            label = 'open url',
            patterns = {
                '\\((https?://\\S+)\\)',
                '\\[(https?://\\S+)\\]',
                '\\{(https?://\\S+)\\}',
                '<(https?://\\S+)>',
                '\\bhttps?://\\S+[)/a-zA-Z0-9-]+'
            },
            action = wezterm.action_callback(function(window, pane)
                local url = window:get_selection_text_for_pane(pane)
                wezterm.log_info('opening: ' .. url)
                wezterm.open_with(url)
            end),
        }),
    },

    -- cursor movement --
    { key = 'LeftArrow',  mods = mod.SUPER,     action = act.SendString '\u{1b}OH' },
    { key = 'RightArrow', mods = mod.SUPER,     action = act.SendString '\u{1b}OF' },
    { key = 'Backspace',  mods = mod.SUPER,     action = act.SendString '\u{15}' },

    -- copy/paste --
    { key = 'c',          mods = mod.REV_SHIFT,  action = act.CopyTo('Clipboard') },
    { key = 'v',          mods = mod.REV_SHIFT,  action = act.PasteFrom('Clipboard') },

    -- tabs --
    -- tabs: spawn+close
    { key = 't',          mods = mod.SUPER,     action = act.SpawnTab('DefaultDomain') },
    { key = 't',          mods = mod.SUPER_REV, action = act.SpawnTab({ DomainName = 'WSL:Ubuntu' }) },
    { key = 'w',          mods = mod.SUPER_REV, action = act.CloseCurrentTab({ confirm = false }) },

    -- tabs: navigation
    { key = 'p',          mods = mod.SUPER_REV,     action = act.ActivateTabRelative(-1) },
    { key = 'n',          mods = mod.SUPER_REV,     action = act.ActivateTabRelative(1) },
    -- { key = 'f',          mods = mod.SUPER_REV, action = act.MoveTabRelative(-1) },
    -- { key = 'b',          mods = mod.SUPER_REV, action = act.MoveTabRelative(1) },

    -- tab: title
    { key = '0',          mods = mod.SUPER,     action = act.EmitEvent('tabs.manual-update-tab-title') },
    { key = '0',          mods = mod.SUPER_REV, action = act.EmitEvent('tabs.reset-tab-title') },

    -- tab: hide tab-bar
    { key = '9',          mods = mod.SUPER,     action = act.EmitEvent('tabs.toggle-tab-bar'), },

    -- window --
    -- window: spawn windows
    { key = 'n',          mods = mod.SUPER,     action = act.SpawnWindow },

    -- window: zoom window
    {
        key = '-',
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            local dimensions = window:get_dimensions()
            if dimensions.is_full_screen then
                return
            end
            local new_width = dimensions.pixel_width - 50
            local new_height = dimensions.pixel_height - 50
            window:set_inner_size(new_width, new_height)
        end)
    },
    {
        key = '=',
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            local dimensions = window:get_dimensions()
            if dimensions.is_full_screen then
                return
            end
            local new_width = dimensions.pixel_width + 50
            local new_height = dimensions.pixel_height + 50
            window:set_inner_size(new_width, new_height)
        end)
    },

    -- background controls --
    {
        key = [[/]],
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:random(window)
        end),
    },
    {
        key = [[,]],
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:cycle_back(window)
        end),
    },
    {
        key = [[.]],
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:cycle_forward(window)
        end),
    },
    {
        key = [[/]],
        mods = mod.SUPER_REV,
        action = act.InputSelector({
            title = 'InputSelector: Select Background',
            choices = backdrops:choices(),
            fuzzy = true,
            fuzzy_description = 'Select Background: ',
            action = wezterm.action_callback(function(window, _pane, idx)
                if not idx then
                    return
                end
                ---@diagnostic disable-next-line: param-type-mismatch
                backdrops:set_img(window, tonumber(idx))
            end),
        }),
    },
    -- {
    --     key = 'b',
    --     mods = mod.SUPER,
    --     action = wezterm.action_callback(function(window, _pane)
    --         backdrops:toggle_focus(window)
    --     end)
    -- },

    -- panes --
    -- panes: split panes
    {
        key = [[\]],
        mods = mod.SUPER,
        action = act.SplitVertical({ domain = 'CurrentPaneDomain' }),
    },
    {
        key = [[\]],
        mods = mod.SUPER_REV,
        action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }),
    },

    -- panes: zoom+close pane
    { key = 'Enter', mods = mod.SUPER,     action = act.TogglePaneZoomState },
    { key = 'w',     mods = mod.SUPER,     action = act.CloseCurrentPane({ confirm = false }) },

    -- panes: navigation
    { key = 'k',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Up') },
    { key = 'j',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Down') },
    { key = 'h',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Left') },
    { key = 'l',     mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Right') },
    -- {
    --     key = 'p',
    --     mods = mod.SUPER_REV,
    --     action = act.PaneSelect({ alphabet = '1234567890', mode = 'SwapWithActiveKeepFocus' }),
    -- },

    -- panes: scroll pane
    { key = 'u',        mods = mod.SUPER, action = act.ScrollByLine(-5) },
    { key = 'd',        mods = mod.SUPER, action = act.ScrollByLine(5) },
    { key = 'PageUp',   mods = 'NONE',    action = act.ScrollByPage(-0.75) },
    { key = 'PageDown', mods = 'NONE',    action = act.ScrollByPage(0.75) },

    -- key-tables --
    -- resizes fonts
    {
        key = 'f',
        mods = 'LEADER',
        action = act.ActivateKeyTable({
            name = 'resize_font',
            one_shot = false,
            timemout_miliseconds = 1000,
        }),
    },
    -- resize panes
    {
        key = 'p',
        mods = 'LEADER',
        action = act.ActivateKeyTable({
            name = 'resize_pane',
            one_shot = false,
            timemout_miliseconds = 1000,
        }),
    },

    {key="a", mods="SUPER", action=act.AttachDomain "mux" },
    {key="d", mods="SUPER", action=act.DetachDomain {DomainName = "mux"}},
    {
    key="$", mods="SUPER",
    action=act.PromptInputLine {
      description = "New session name:",
      action = wezterm.action_callback(function(_, pane, line)
        if line and #line > 0 then
          mux.rename_workspace(pane:mux_window():get_workspace(), line)
        end
      end),
    }
  },
}

for k, v in pairs(mac_keys) do
   table.insert(keys, v)
end

-- stylua: ignore
local key_tables = {
    resize_font = {
        { key = 'k',      action = act.IncreaseFontSize },
        { key = 'j',      action = act.DecreaseFontSize },
        { key = 'r',      action = act.ResetFontSize },
        { key = 'Escape', action = 'PopKeyTable' },
        { key = 'q',      action = 'PopKeyTable' },
    },
    resize_pane = {
        { key = 'k',      action = act.AdjustPaneSize({ 'Up', 1 }) },
        { key = 'j',      action = act.AdjustPaneSize({ 'Down', 1 }) },
        { key = 'h',      action = act.AdjustPaneSize({ 'Left', 1 }) },
        { key = 'l',      action = act.AdjustPaneSize({ 'Right', 1 }) },
        { key = 'Escape', action = 'PopKeyTable' },
        { key = 'q',      action = 'PopKeyTable' },
    },
}

local mouse_bindings = {
   -- Ctrl-click will open the link under the mouse cursor
   {
      event = { Up = { streak = 1, button = 'Left' } },
      mods = 'CTRL',
      action = act.OpenLinkAtMouseCursor,
   },
}
print(keys)

return {
   disable_default_key_bindings = true,
   -- disable_default_mouse_bindings = true,
   leader = { key = 'Space', mods = mod.SUPER_REV },
   keys = keys,
   key_tables = key_tables,
   mouse_bindings = mouse_bindings,
}
