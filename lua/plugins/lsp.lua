return {
    {
        "mason-org/mason.nvim",
        config = function()
            require("mason").setup({
                registries = {
                    "github:mason-org/mason-registry",
                    "github:Crashdummyy/mason-registry",
                },
            })
        end,
    },
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = {
            "mason-org/mason.nvim",
            "neovim/nvim-lspconfig",
        },
        opts = {
            ensure_installed = {
                "lua_ls",
                "ts_ls",
                "html",
                "cssls",
                "pyright",
                "bashls",
                "clangd",
                "arduino_language_server",
            },
            -- arduino is started manually (see FileType autocmd below) so the
            -- board (fqbn) can be picked per-sketch. Let mason enable the rest.
            automatic_enable = { exclude = { "arduino_language_server" } },
        },
    },
    {
        "WhoIsSethDaniel/mason-tool-installer.nvim",
        dependencies = { "mason-org/mason.nvim" },
        opts = {
            ensure_installed = {
                "roslyn",
            },
        },
    },
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "williamboman/mason-lspconfig.nvim",
            "saghen/blink.cmp",
        },
        config = function()
            require("keymaps").lsp()

            -- Using the HEAD syntax as requested
            vim.lsp.enable("lua_ls")
            vim.lsp.enable("ts_ls")
            vim.lsp.enable("html")
            vim.lsp.enable("cssls")
            vim.lsp.enable("bashls")
            -- vim.lsp.enable("pyright")
            vim.lsp.enable("hls")
            vim.lsp.enable("clangd")
            -- dartls is started by flutter-tools (plugins/flutter_tools.lua)
            vim.lsp.enable("rust_analyzer")

            -- Arduino (.ino) — arduino-language-server wraps clangd and needs a
            -- board (fqbn) up front. The server's -fqbn flag wins over sketch.yaml,
            -- so we read the board per-sketch ourselves: put a sketch.yaml next to
            -- the .ino with e.g. `default_fqbn: esp32:esp32:esp32`. Falls back to
            -- an Uno when no sketch.yaml is found.
            local function arduino_fqbn(bufnr)
                local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
                local sketch = vim.fs.find("sketch.yaml", { path = dir, upward = true })[1]
                if sketch then
                    for line in io.lines(sketch) do
                        local fqbn = line:match("^%s*default_fqbn%s*:%s*(%S+)")
                        if fqbn then
                            return fqbn
                        end
                    end
                end
                return "arduino:avr:uno"
            end

            -- arduino-language-server 0.7.7 panics on `workspace/semanticTokens/refresh`,
            -- which clangd only sends because Neovim advertises refreshSupport. Drop
            -- that one capability for this client so clangd never sends it.
            local arduino_caps = vim.lsp.protocol.make_client_capabilities()
            arduino_caps.workspace.semanticTokens.refreshSupport = false

            local function start_arduino_lsp(bufnr)
                local root = vim.fs.root(bufnr, { "sketch.yaml", ".git" })
                    or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
                vim.lsp.start({
                    name = "arduino_language_server",
                    capabilities = arduino_caps,
                    cmd = {
                        "arduino-language-server",
                        "-cli-config", vim.fn.expand("~/.arduino15/arduino-cli.yaml"),
                        "-fqbn", arduino_fqbn(bufnr),
                        "-cli", vim.fn.exepath("arduino-cli"),
                        "-clangd", vim.fn.exepath("clangd"),
                    },
                    root_dir = root,
                })
            end

            vim.api.nvim_create_autocmd("FileType", {
                pattern = "arduino",
                callback = function(ev)
                    start_arduino_lsp(ev.buf)
                end,
            })

            -- Cover buffers already open when this config loads (e.g. `nvim x.ino`),
            -- since their FileType event fired before the autocmd was registered.
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "arduino" then
                    start_arduino_lsp(buf)
                end
            end

            require("scripts.format_on_save")
        end,
    },
}
