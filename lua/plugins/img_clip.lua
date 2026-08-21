-- Klistra in bilder från clipboardet, som Obsidian. I vaultet hamnar de i
-- "09 - Inline media" med Obsidians namngivning och en ![[wikilink]], så
-- både Obsidian och snacks.image renderar dem.
return {
    {
        "HakonHarnes/img-clip.nvim",
        ft = "markdown",
        cmd = "PasteImage",
        keys = {
            { "<leader>ip", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
        },
        opts = {
            default = {
                prompt_for_file_name = false,
            },
            dirs = {
                ["obsidian"] = {
                    default = {
                        dir_path = vim.fn.expand("~/obsidian/09 - Inline media"),
                        file_name = "Pasted image %Y%m%d%H%M%S",
                        relative_to_current_file = false,
                        use_absolute_path = false,
                        template = "![[$FILE_NAME]]",
                    },
                },
            },
        },
    },
}
