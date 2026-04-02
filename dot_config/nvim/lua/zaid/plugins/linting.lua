-- Linting via nvim-lint
-- Only for tools not covered by an LSP (ruff LSP handles Python linting)

return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")

		lint.linters_by_ft = {
			go = { "golangcilint" }, -- comprehensive Go linting (configure via .golangci.yml)
			yaml = { "yamllint" }, -- style checks (configure via .yamllint to avoid prettier conflicts)
			-- Python: handled by ruff LSP (see lspconfig.lua)
			-- Bash: handled by bash-language-server + shellcheck (see lspconfig.lua)
			-- Terraform: handled by tflint LSP (see lspconfig.lua)
		}

		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
			group = vim.api.nvim_create_augroup("lint", { clear = true }),
			callback = function()
				lint.try_lint()
			end,
		})

		vim.keymap.set("n", "<leader>l", function()
			lint.try_lint()
		end, { desc = "Trigger linting for current file" })
	end,
}
