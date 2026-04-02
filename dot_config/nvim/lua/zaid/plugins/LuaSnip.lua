return {
	"L3MON4D3/LuaSnip",
	version = "v2.*",
	build = "make install_jsregexp",
	dependencies = {
		"rafamadriz/friendly-snippets",
	},
	config = function()
		local luasnip = require("luasnip")

		-- Load VSCode-style snippets from friendly-snippets
		require("luasnip.loaders.from_vscode").lazy_load()

		-- Load custom snippets from zaid/snippets/ folder
		local custom_snippets = {
			-- Add languages here as { filetype = "filename_without_extension" }
			-- Example: { filetype = "lua", file = "lua" },
		}

		for _, snippet_info in ipairs(custom_snippets) do
			local path = "zaid.plugins.snippets." .. snippet_info.file
			local ok, snippets = pcall(require, path)
			if ok and type(snippets) == "table" then
				luasnip.add_snippets(snippet_info.filetype, snippets)
			end
		end
	end,
}
