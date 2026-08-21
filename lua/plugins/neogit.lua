return {
    {
        "NeogitOrg/neogit",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "dlyongemallo/diffview.nvim",
        },
        config = function()
            require('keymaps').git_diff()
        end
    },
    {
        -- Maintained fork of sindrets/diffview.nvim with a jj adapter.
        "dlyongemallo/diffview.nvim",
        -- In a colocated repo both adapters match; jj is the one we work in.
        opts = { preferred_adapter = "jj" },
    },
}
