-- Rio speaks the kitty graphics protocol but snacks only auto-detects
-- kitty/ghostty/wezterm, so force it on.
vim.env.SNACKS_KITTY = "1"

-- Rio can't render images the way snacks sends them, for two reasons:
--  * it runs on the Windows side and can't read WSL paths, so images must
--    be sent as data (t=d), never as file paths (t=f)
--  * it doesn't implement standalone virtual placements (a=t + a=p draws
--    nothing, while a=T,U=1 with the data inline works)
-- So: skip snacks' own transmit, and when it asks for a placement, send the
-- whole image as a chunked a=T,U=1 instead.
local function rio_image_fix()
    local Image = require("snacks.image.image")
    local term = require("snacks.image.terminal")
    local files = {} ---@type table<number, string> image id -> png file

    function Image:send()
        files[self.id] = self.file
        self.sent = true
        self:on_send()
    end

    local request = term.request
    function term.request(o)
        local file = o.a == "p" and o.U and files[o.i]
        if not file then
            return request(o)
        end
        local fd = io.open(file, "rb")
        if not fd then
            return
        end
        local data = vim.base64.encode(fd:read("*a"))
        fd:close()
        local pos, first = 1, true
        while pos <= #data do
            local chunk = data:sub(pos, pos + 4095)
            pos = pos + 4096
            local m = pos <= #data and 1 or 0
            if first then
                -- no p= here: rio draws nothing when a placement id is given
                request({ a = "T", U = 1, t = "d", f = 100, i = o.i, c = o.c, r = o.r, m = m, data = chunk })
                first = false
            else
                request({ m = m, data = chunk })
            end
        end
    end
end

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
                win = {
                    input = {
                        keys = {
                            ["<C-a>"] = { "qflist", mode = { "i", "n" } },
                        },
                    },
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
        config = function(_, opts)
            require("snacks").setup(opts)
            rio_image_fix()
        end,
    }
}
