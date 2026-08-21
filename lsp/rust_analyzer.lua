-- checkOnSave runs `cargo check --all-targets` in the project's own target/ by
-- default, which means a save takes the same cargo build-directory lock as a
-- deploy or `sqlx prepare` running in that worktree, and the two block each
-- other. targetDir = true moves the check into target/rust-analyzer.
return {
    settings = {
        ["rust-analyzer"] = {
            cargo = {
                targetDir = true,
            },
        },
    },
}
