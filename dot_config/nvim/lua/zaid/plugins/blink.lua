return {
	"saghen/blink.cmp",
	version = "1.*",
	event = "InsertEnter",
	dependencies = {
		"L3MON4D3/LuaSnip",
		"rafamadriz/friendly-snippets",
		"onsails/lspkind.nvim",
		{
			"supermaven-inc/supermaven-nvim",
			opts = {
				disable_inline_completion = true,
				disable_keymaps = true,
				log_level = "off",
			},
		},
		{ "huijiro/blink-cmp-supermaven" },
	},

	---@module 'blink.cmp'
	---@type blink.cmp.Config
	opts = {
		snippets = { preset = "luasnip" },

		sources = {
			default = { "lsp", "path", "snippets", "buffer", "supermaven" },
			providers = {
				supermaven = {
					name = "Supermaven",
					module = "blink-cmp-supermaven",
					async = true,
					score_offset = 100,
					-- Strip documentation to prevent preview window overlap
					transform_items = function(_, items)
						for _, item in ipairs(items) do
							item.documentation = nil
						end
						return items
					end,
				},
			},
		},

		keymap = {
			preset = "none",

			-- Menu navigation
			["<C-n>"] = { "select_next", "snippet_forward", "fallback" },
			["<C-p>"] = { "select_prev", "snippet_backward", "fallback" },

			-- Confirm selection
			["<C-y>"] = { "select_and_accept", "fallback" },

			-- Abort/hide
			["<C-e>"] = { "hide", "fallback" },

			-- Tab/S-Tab for navigation + snippet jumping
			["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
			["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },

			-- Arrow key navigation
			["<Down>"] = { "select_next", "fallback" },
			["<Up>"] = { "select_prev", "fallback" },

			-- Snippet jumping (dedicated keys)
			["<C-j>"] = { "snippet_forward", "fallback" },
			["<C-k>"] = { "snippet_backward", "fallback" },

			-- Manual trigger
			["<C-x>"] = { "show", "fallback" },

			-- Snippet-only trigger
			["<C-f>"] = {
				function(cmp)
					cmp.show({ providers = { "snippets" } })
				end,
				"fallback",
			},

			-- Documentation scrolling
			["<C-d>"] = { "scroll_documentation_down", "fallback" },
			["<C-u>"] = { "scroll_documentation_up", "fallback" },
		},

		completion = {
			list = {
				selection = { preselect = true, auto_insert = false },
			},
			menu = {
				border = "rounded",
				draw = {
					treesitter = { "lsp" },
					columns = {
						{ "kind_icon" },
						{ "label", "label_description", gap = 1 },
						{ "source_name" },
					},
					components = {
						kind_icon = {
							text = function(ctx)
								local icon = require("lspkind").symbolic(ctx.kind, { mode = "symbol" })
								if icon and icon ~= "" then
									return icon .. ctx.icon_gap
								end
								return ctx.kind_icon .. ctx.icon_gap
							end,
							highlight = function(ctx)
								return ctx.kind_hl
							end,
						},
						source_name = {
							width = { max = 30 },
							text = function(ctx)
								return "[" .. ctx.source_name .. "]"
							end,
							highlight = "BlinkCmpSource",
						},
					},
				},
			},
			documentation = {
				auto_show = false,
				window = { border = "rounded" },
			},
			ghost_text = { enabled = true },
		},

		appearance = {
			nerd_font_variant = "mono",
		},

		signature = {
			enabled = true,
			window = { border = "rounded" },
		},
	},
	opts_extend = { "sources.default" },
}
