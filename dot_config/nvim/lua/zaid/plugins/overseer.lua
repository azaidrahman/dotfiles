-- Language-agnostic "run current file" + errors -> quickfix/diagnostics.
-- Supersedes the Go-only M.go_run() in core/makerun.lua: one keymap, filetype
-- picks the command, output is parsed with :help errorformat instead of a
-- hand-rolled regex.
return {
	"stevearc/overseer.nvim",
	cmd = { "OverseerRun", "OverseerToggle" },
	keys = {
		{
			"<leader>qg",
			function() require("overseer").run_task({ name = "run script" }) end,
			desc = "Run current file, errors -> quickfix",
		},
		{ "<leader>qt", "<cmd>OverseerToggle<CR>", desc = "Toggle Overseer task list" },
	},
	opts = {
		task_list = {
			direction = "bottom",
			min_height = 10,
			max_height = 0.4,
			bindings = {
				-- Close the task list window with a plain `q` while focused in it.
				["q"] = "Close",
			},
		},
	},
	config = function(_, opts)
		local overseer = require("overseer")
		overseer.setup(opts)

		-- One template, dispatched by filetype. Add a language by adding a
		-- branch here and its filetype to `condition.filetype` below.
		overseer.register_template({
			name = "run script",
			builder = function()
				local file = vim.fn.expand("%:p")
				local cmd = { file }
				if vim.bo.filetype == "go" then
					cmd = { "go", "run", file }
				elseif vim.bo.filetype == "python" then
					cmd = { "python3", file }
				elseif vim.bo.filetype == "javascript" then
					cmd = { "node", file }
				elseif vim.bo.filetype == "typescript" then
					cmd = { "npx", "tsx", file }
				elseif vim.bo.filetype == "rust" then
					cmd = { "cargo", "run" }
				elseif vim.bo.filetype == "sh" or vim.bo.filetype == "bash" then
					cmd = { "bash", file }
				end
				return {
					cmd = cmd,
					cwd = vim.fn.expand("%:p:h"),
					components = {
						-- Parses errorformat matches into quickfix and, via
						-- set_diagnostics, into vim.diagnostic too (so [d/]d
						-- and gutter signs work without opening quickfix at all).
						{ "on_output_quickfix", open = true, open_height = 12, set_diagnostics = true },
						"default",
					},
				}
			end,
			condition = {
				filetype = { "go", "python", "javascript", "typescript", "rust", "sh", "bash" },
			},
		})
	end,
}
