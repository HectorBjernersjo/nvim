-- Rio speaks the kitty graphics protocol but snacks only auto-detects
-- kitty/ghostty/wezterm, so force it on.
vim.env.SNACKS_KITTY = "1"

return {
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        ---@type snacks.Config
        opts = {
            animate = { enabled = false },
            bigfile = { enabled = true },
            bufdelete = { enabled = false },
            dashboard = { enabled = false },
            debug = { enabled = false },
            dim = { enabled = false },
            explorer = { enabled = false },
            git = { enabled = true },
            gitbrowse = { enabled = false },
            image = {
                enabled = true,
                resolve = function(file, src)
                    -- Obsidian puts pasted images in "09 - Inline media",
                    -- so ![[Pasted image ...png]] resolves against it.
                    if file:find("/obsidian/", 1, true) then
                        local p = vim.fs.normalize("~/obsidian/09 - Inline media/" .. src)
                        if vim.fn.filereadable(p) == 1 then
                            return p
                        end
                    end
                end,
            },
            indent = { enabled = false },
            input = { enabled = false },
            layout = { enabled = false },
            lazygit = { enabled = false },
            notifier = { enabled = false },
            notify = { enabled = false },
            picker = {
                enabled = true,
                layout = {
                    preset = 'telescope'
                },
                matcher = {
                    cwd_bonus = false,
                    frecency = true,
                    history_bonus = true,
                },
                debug = {
                    scores = true,
                },
            },
            profiler = { enabled = false },
            quickfile = { enabled = false },
            rename = { enabled = false },
            scope = { enabled = false },
            scratch = { enabled = false },
            scroll = { enabled = false },
            statuscolumn = { enabled = false },
            terminal = { enabled = false },
            toggle = { enabled = false },
            util = { enabled = false },
            win = { enabled = false },
            words = { enabled = false },
            zen = { enabled = true }
        },
        keys = require('keymaps').snacks,
    }
}
