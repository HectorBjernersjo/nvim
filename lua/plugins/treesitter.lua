return {
    {                                -- Highlight, edit, and navigate code
        'nvim-treesitter/nvim-treesitter',
        branch = 'main',             -- the `master` branch is frozen and does NOT support Neovim 0.12
        lazy = false,                -- main does not support lazy-loading
        build = ':TSUpdate',
        config = function()
            local ts = require('nvim-treesitter')
            ts.setup()

            -- Parsers to always have available. Installed asynchronously;
            -- this is a no-op for parsers that are already installed.
            local ensure_installed = {
                'bash', 'c', 'dart', 'diff', 'html', 'lua', 'luadoc',
                'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc',
            }
            ts.install(ensure_installed)

            -- Languages where we want highlighting but NOT treesitter indent.
            local no_ts_indent = { ruby = true }

            -- Enable highlighting + indentation per filetype, auto-installing
            -- the parser on demand (replaces the old `auto_install = true`).
            vim.api.nvim_create_autocmd('FileType', {
                desc = 'Start treesitter highlighting/indent (auto-install parser)',
                callback = function(ev)
                    local ft = vim.bo[ev.buf].filetype
                    if ft == '' then return end
                    local lang = vim.treesitter.language.get_lang(ft) or ft

                    local function start()
                        if not pcall(vim.treesitter.start, ev.buf, lang) then return end
                        if not no_ts_indent[ft] then
                            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                        end
                    end

                    if vim.list_contains(ts.get_installed(), lang) then
                        start()
                    elseif vim.list_contains(ts.get_available(), lang) then
                        -- Parser not installed yet but supported: install, then start.
                        ts.install({ lang }):await(function()
                            vim.schedule(function()
                                if vim.api.nvim_buf_is_valid(ev.buf) then start() end
                            end)
                        end)
                    end
                end,
            })
        end,
    },
}
