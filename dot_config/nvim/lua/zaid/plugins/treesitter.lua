return {
	-- NOTE: nvim-treesitter on `main` branch (required for Neovim 0.12+)
	-- The old `master` branch API (require("nvim-treesitter.configs").setup()) is frozen/deprecated.
	-- Neovim 0.12 handles highlighting & indentation natively via vim.treesitter.start()
	-- The plugin now only manages parser installation.
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false, -- must load early so parsers are available
		build = ":TSUpdate",
		config = function()
			-- setup() configures where parsers get installed
			require("nvim-treesitter").setup({
				install_dir = vim.fn.stdpath("data") .. "/site",
			})

			-- install() downloads pre-compiled parsers (async, won't block startup)
			-- add/remove languages here as needed
			require("nvim-treesitter").install({
				"json",
				"javascript",
				"typescript",
				"tsx",
				"go",
				"yaml",
				"html",
				"css",
				"python",
				"http",
				-- "prisma",
				"markdown",
				"markdown_inline",
				-- "svelte",
				-- "graphql",
				"bash",
				"lua",
				"vim",
				"dockerfile",
				"gitignore",
				"query",
				"vimdoc",
				"c",
				-- "java",
				-- "rust",
				"helm",
			})

			-- Enable treesitter highlighting + indentation for every filetype that has a parser
			-- This replaces the old `highlight = { enable = true }` and `indent = { enable = true }`
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("TreesitterSetup", { clear = true }),
				callback = function(args)
					local ft = args.match
					-- get_lang maps filetype → treesitter language name (e.g. "typescriptreact" → "tsx")
					local lang = vim.treesitter.language.get_lang(ft) or ft
					-- inspect checks if the parser is actually installed
					local ok = pcall(vim.treesitter.language.inspect, lang)
					if ok then
						-- start() enables treesitter syntax highlighting for this buffer
						vim.treesitter.start()
						-- indentexpr enables treesitter-based auto-indentation
						vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})

			-- NOTE: Incremental selection is now built-in (Neovim 0.12+)
			-- Use `an` to expand selection outward and `in` to shrink inward (visual mode)
			-- This replaces the old `incremental_selection` module with <C-S-Space>
		end,
	},
	-- NOTE: Auto close/rename HTML-style tags (works independently of treesitter module system)
	{
		"windwp/nvim-ts-autotag",
		ft = { "html", "xml", "svelte" },
		config = function()
			require("nvim-ts-autotag").setup({
				opts = {
					enable_close = true, -- Auto-close tags
					enable_rename = true, -- Auto-rename pairs
					enable_close_on_slash = false, -- Disable auto-close on trailing `</`
				},
				per_filetype = {
					["html"] = {
						enable_close = true,
					},
				},
			})
		end,
	},
}
