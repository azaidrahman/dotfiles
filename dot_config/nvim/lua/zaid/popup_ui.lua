-- Reusable "look & feel" for standalone/minimal Neovim instances launched by
-- scripts (e.g. the tmux diff-review popup) that load NONE of the normal config.
-- Mirrors the main config's theme (tokyonight) + statusline (lualine), but as an
-- explicit, opt-in applier so any script can get the same look in one call:
--
--   -- in a script's -u init, make this module requireable, then:
--   package.path = vim.fn.stdpath("config") .. "/lua/?.lua;"
--     .. vim.fn.stdpath("config") .. "/lua/?/init.lua;" .. package.path
--   pcall(function() require("zaid.popup_ui").apply() end)
--
-- Everything is rtp-prepended on demand and pcall-guarded, so a missing plugin
-- degrades to the plain UI rather than erroring the script.

local M = {}

local function prepend_plugin(name)
  vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/" .. name)
end

-- Theme + filetype icons. Mirrors plugins/colorscheme.lua (tokyonight).
function M.colorscheme()
  prepend_plugin("nvim-web-devicons")
  prepend_plugin("folkeTokyonight")

  local transparent = true
  local bg_highlight = "#143652"
  local bg_search = "#0A64AC"
  local bg_visual = "#275378"
  local fg = "#CBE0F0"
  local fg_dark = "#B4D0E9"
  local fg_gutter = "#627E97"
  local border = "#547998"
  local comment = "#858470"
  require("tokyonight").setup({
    style = "night",
    transparent = transparent,
    styles = {
      comments = { italic = false },
      keywords = { italic = false },
      sidebars = transparent and "transparent" or "dark",
      floats = transparent and "transparent" or "dark",
    },
    on_highlights = function(hl, c)
      hl.NormalFloat = { bg = "#1f2030" }
      hl.FloatBorder = { bg = "#1f2030", fg = "#54546d" }
      hl.FloatTitle = { bg = "#1f2030" }
    end,
    on_colors = function(colors)
      colors.bg = transparent and colors.none or colors.bg
      colors.bg_float = transparent and colors.none or colors.bg_dark
      colors.bg_highlight = bg_highlight
      colors.bg_search = bg_search
      colors.bg_sidebar = transparent and colors.none or colors.bg_dark
      colors.bg_statusline = transparent and colors.none or colors.bg_dark
      colors.bg_visual = bg_visual
      colors.border = border
      colors.fg = fg
      colors.fg_dark = fg_dark
      colors.fg_float = fg
      colors.fg_gutter = fg_gutter
      colors.fg_sidebar = fg_dark
      colors.comment = comment
    end,
  })
  vim.cmd.colorscheme("tokyonight")
end

-- Statusline. Mirrors plugins/lualine.lua (custom theme + sections), as a single
-- global bar, minus the lazy.status component (needs the full lazy runtime).
function M.statusline()
  prepend_plugin("nvim-web-devicons")
  prepend_plugin("lualine.nvim")

  local c = {
    color0 = "#092236", color1 = "#ff5874", color2 = "#c3ccdc", color3 = "#1c1e26",
    color6 = "#a1aab8", color7 = "#828697", color8 = "#ae81ff", color9 = "#5ca0ff",
  }
  local theme = {
    replace = { a = { fg = c.color0, bg = c.color1, gui = "bold" }, b = { fg = c.color2, bg = c.color3 } },
    inactive = { a = { fg = c.color6, bg = c.color3, gui = "bold" }, b = { fg = c.color6, bg = c.color3 }, c = { fg = c.color6, bg = c.color3 } },
    normal = { a = { fg = c.color0, bg = c.color7, gui = "bold" }, b = { fg = c.color2, bg = c.color3 }, c = { fg = c.color2, bg = c.color3 } },
    visual = { a = { fg = c.color0, bg = c.color8, gui = "bold" }, b = { fg = c.color2, bg = c.color3 } },
    insert = { a = { fg = c.color0, bg = c.color9, gui = "bold" }, b = { fg = c.color9, bg = c.color3 } },
  }
  require("lualine").setup({
    options = {
      icons_enabled = true,
      theme = theme,
      globalstatus = true, -- single global bar (matches the main config's laststatus=3)
      component_separators = { left = "|", right = "|" },
      section_separators = { left = "|", right = "" },
    },
    sections = {
      lualine_a = { { "mode", fmt = function(s) return " " .. s end } },
      lualine_b = { { "branch", icon = { "", color = { fg = "#A6D4DE" } } } },
      lualine_c = { { "filename", file_status = true, path = 3 } },
      lualine_x = { { "filetype" } },
    },
  })
end

-- Apply the full look. opts.statusline = false to skip lualine.
function M.apply(opts)
  opts = opts or {}
  vim.o.termguicolors = true
  vim.o.background = "dark"
  pcall(M.colorscheme)
  if opts.statusline ~= false then
    pcall(M.statusline)
  end
end

return M
