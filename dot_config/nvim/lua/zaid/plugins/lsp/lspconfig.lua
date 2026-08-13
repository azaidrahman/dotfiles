-- LSP configuration using Neovim 0.12 native API (vim.lsp.config + vim.lsp.enable)
-- nvim-lspconfig is only loaded for its server config database (cmd, root_dir, filetypes defaults)
-- Mason handles binary installation (see mason.lua)

return {
	"neovim/nvim-lspconfig",
	event = { "BufReadPre", "BufNewFile" },
	dependencies = {
		{ "antosha417/nvim-lsp-file-operations", config = true },
	},
	config = function()
		------------------------------------------------------------
		-- Diagnostics
		------------------------------------------------------------
		vim.diagnostic.config({
			signs = {
				text = {
					[vim.diagnostic.severity.ERROR] = " ",
					[vim.diagnostic.severity.WARN] = " ",
					[vim.diagnostic.severity.HINT] = "󰠠 ",
					[vim.diagnostic.severity.INFO] = " ",
				},
			},
			virtual_text = false,
			underline = true,
			update_in_insert = false,
		})

		------------------------------------------------------------
		-- LSP keymaps (on attach)
		-- Neovim 0.12 defaults: gd gD grn gra grr gri grt K <C-s> [d ]d
		-- We only add custom bindings that aren't covered by defaults
		------------------------------------------------------------
		vim.api.nvim_create_autocmd("LspAttach", {
			group = vim.api.nvim_create_augroup("UserLspConfig", {}),
			callback = function(ev)
				local client = vim.lsp.get_client_by_id(ev.data.client_id)
				local map = function(mode, lhs, rhs, desc)
					vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, silent = true, desc = desc })
				end

				-- Disable hover for ruff (basedpyright handles it)
				if client and client.name == "ruff" then
					client.server_capabilities.hoverProvider = false
				end

				-- Inlay hints toggle (Neovim 0.10+)
				if client and client:supports_method("textDocument/inlayHint") then
					map("n", "<leader>lh", function()
						vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf }), { bufnr = ev.buf })
					end, "Toggle inlay hints")
				end

				-- Custom keymaps (not covered by 0.12 defaults)
				map("n", "<leader>rn", vim.lsp.buf.rename, "Smart rename")
				map("n", "<leader>D", function()
					require("snacks").picker.diagnostics({ filter = { buf = 0 } })
				end, "Show buffer diagnostics")
				map("n", "<leader>d", vim.diagnostic.open_float, "Show line diagnostics")
				map("n", "<leader>rs", "<cmd>LspRestart<CR>", "Restart LSP")
			end,
		})

		------------------------------------------------------------
		-- Server configurations
		-- Only specify settings that differ from nvim-lspconfig defaults
		------------------------------------------------------------
		local servers = {
			lua_ls = {
				-- lazydev.nvim handles workspace/globals, just set completion style
				settings = {
					Lua = {
						completion = { callSnippet = "Replace" },
					},
				},
			},

			emmet_language_server = {
				filetypes = {
					"css", "eruby", "html", "less", "sass", "scss", "pug",
				},
			},

			ruff = {
				init_options = {
					settings = {
						lint = { args = { "--select=E,F,I" } },
					},
				},
			},

			yamlls = {
				capabilities = {
					textDocument = {
						foldingRange = { dynamicRegistration = false, lineFoldingOnly = true },
					},
				},
				settings = {
					redhat = { telemetry = { enabled = false } },
					yaml = {
						schemaStore = {
							enable = true,
							url = "https://www.schemastore.org/api/json/catalog.json",
						},
						format = { enabled = false },
						-- enabling this conflicts between Kubernetes resources, kustomization.yaml, and Helmreleases
						validate = false,
						schemas = {
							-- GCP IAM roles for the member_roles.yaml registries. The schema is
							-- generated locally by ~/.local/bin/gcp-roles-schema, because the role
							-- list is account-specific and the custom roles are internal. It is not
							-- in this repository. If the file is absent, yamlls ignores the entry.
							[vim.fn.expand("~/.local/share/gcp-roles/member-roles.schema.json")] = "**/registry/member_roles.{yml,yaml}",
							kubernetes = "*.yaml",
							["http://json.schemastore.org/github-workflow"] = ".github/workflows/*",
							["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
							["https://raw.githubusercontent.com/microsoft/azure-pipelines-vscode/master/service-schema.json"] = "azure-pipelines*.{yml,yaml}",
							["https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json#/$defs/tasks"] = "roles/tasks/*.{yml,yaml}",
							["https://raw.githubusercontent.com/ansible/ansible-lint/main/src/ansiblelint/schemas/ansible.json#/$defs/playbook"] = "*play*.{yml,yaml}",
							["http://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
							["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
							["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
							["https://json.schemastore.org/dependabot-v2"] = ".github/dependabot.{yml,yaml}",
							["https://gitlab.com/gitlab-org/gitlab/-/raw/master/app/assets/javascripts/editor/schema/ci.json"] = "*gitlab-ci*.{yml,yaml}",
							["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json"] = "*api*.{yml,yaml}",
							["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "*docker-compose*.{yml,yaml}",
							["https://raw.githubusercontent.com/argoproj/argo-workflows/master/api/jsonschema/schema.json"] = "*flow*.{yml,yaml}",
						},
					},
				},
			},

			gopls = {
				settings = {
					gopls = {
						gofumpt = true, -- stricter formatting than gofmt
						staticcheck = true, -- extra static analysis
						analyses = {
							unusedparams = true,
							shadow = true,
						},
					},
				},
			},

			-- bash-language-server auto-integrates shellcheck (if on PATH) for linting
			bashls = {},

			-- tflint runs as a second LSP alongside terraformls for real-time terraform linting
			tflint = {},

			-- Servers with no custom config (just need to be enabled)
			html = {},
			cssls = {},
			marksman = {},
			basedpyright = {},
			terraformls = {},
			groovyls = {},
			helm_ls = {},
		}

		------------------------------------------------------------
		-- Apply configs and enable all servers
		------------------------------------------------------------
		local server_names = {}
		for name, config in pairs(servers) do
			vim.lsp.config(name, config)
			table.insert(server_names, name)
		end
		vim.lsp.enable(server_names)
	end,
}
