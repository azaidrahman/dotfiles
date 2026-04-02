-- Mason: package manager for LSP servers, formatters, and linters
-- All tool installation is consolidated here in one list

return {
	"williamboman/mason.nvim",
	lazy = false,
	dependencies = {
		"WhoIsSethDaniel/mason-tool-installer.nvim",
	},
	config = function()
		require("mason").setup({
			ui = {
				border = "rounded",
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		})

		require("mason-tool-installer").setup({
			ensure_installed = {
				-- LSP servers (mason package names → lspconfig names)
				"lua-language-server", -- lua_ls
				"html-lsp", -- html
				"css-lsp", -- cssls
				"gopls", -- gopls
				"yaml-language-server", -- yamlls
				"emmet-language-server", -- emmet_language_server
				"marksman", -- marksman
				"basedpyright", -- basedpyright
				"ruff", -- ruff (Python lint + format)
				"terraform-ls", -- terraformls
				"tflint", -- tflint (Terraform linting LSP)
				"bash-language-server", -- bashls
				"groovy-language-server", -- groovyls

				-- Formatters
				"prettier",
				"stylua",
				"shfmt",
				"goimports", -- Go import organization
				"gofumpt", -- Go strict formatting (superset of gofmt)

				-- Linters
				"shellcheck", -- used by bash-language-server for shell linting
				"golangci-lint", -- comprehensive Go linting (100+ linters)
				"yamllint", -- YAML style linting (line length, spacing, etc)

				-- Additional formatters used in conform.nvim
				"beautysh", -- zsh formatting
				"markdownlint-cli2", -- markdown linting/formatting
				"markdown-toc", -- markdown table of contents
			},
		})
	end,
}
