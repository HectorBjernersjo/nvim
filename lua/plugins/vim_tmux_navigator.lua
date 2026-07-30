return {
    {
        "christoomey/vim-tmux-navigator",
        -- Don't wrap to the opposite side of the window at an edge pane; must
        -- be set before the plugin loads. Mirrors the pane_at_* guards in
        -- tmux.conf.
        init = function()
            vim.g.tmux_navigator_no_wrap = 1
        end,
        config = function()
            require('keymaps').vim_tmux_navigator()
        end
    },
}
