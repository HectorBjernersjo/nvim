-- Flutter/Dart. flutter-tools starts dartls itself (via the `flutter` on PATH),
-- so dartls must NOT also be enabled in plugins/lsp.lua.
return {
    {
        "nvim-flutter/flutter-tools.nvim",
        ft = "dart",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "mfussenegger/nvim-dap",
        },
        opts = {
            debugger = {
                enabled = true,
            },
            widget_guides = {
                enabled = true,
            },
            dev_log = {
                open_cmd = "botright 15split",
            },
            lsp = {
                on_attach = function(_, bufnr)
                    vim.lsp.document_color.enable(true, { bufnr = bufnr })
                end,
                settings = {
                    showTodos = false,
                    completeFunctionCalls = true,
                    renameFilesWithClasses = "prompt",
                    enableSnippets = true,
                    updateImportsOnRename = true,
                },
            },
        },
        keys = {
            { "<leader>fr", "<cmd>FlutterRun<CR>",          ft = "dart", desc = "Flutter run" },
            { "<leader>fq", "<cmd>FlutterQuit<CR>",         ft = "dart", desc = "Flutter quit" },
            { "<leader>fh", "<cmd>FlutterReload<CR>",       ft = "dart", desc = "Flutter hot reload" },
            { "<leader>fR", "<cmd>FlutterRestart<CR>",      ft = "dart", desc = "Flutter hot restart" },
            { "<leader>fd", "<cmd>FlutterDevices<CR>",      ft = "dart", desc = "Flutter devices" },
            { "<leader>fe", "<cmd>FlutterEmulators<CR>",    ft = "dart", desc = "Flutter emulators" },
            { "<leader>fl", "<cmd>FlutterLogToggle<CR>",    ft = "dart", desc = "Flutter log" },
            { "<leader>fo", "<cmd>FlutterOutlineToggle<CR>", ft = "dart", desc = "Flutter widget outline" },
        },
    },
}
