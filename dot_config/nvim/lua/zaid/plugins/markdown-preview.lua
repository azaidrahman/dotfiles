return {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = "cd app && yarn install",
    init = function()
        local reader_style = "sepia" -- sepia, paper, or obsidian
        local css_dir = vim.fn.stdpath("config") .. "/assets/markdown-preview"

        vim.g.mkdp_filetypes = { "markdown" }
        vim.g.mkdp_theme = "light"
        vim.g.mkdp_markdown_css = string.format("%s/%s.css", css_dir, reader_style)
        vim.g.mkdp_page_title = "${name} - Markdown"
        vim.g.mkdp_preview_options = {
            disable_filename = 1,
            hide_yaml_meta = 1,
            sync_scroll_type = "middle",
        }
    end,
}
