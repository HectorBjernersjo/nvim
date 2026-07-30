local M = {}

local SQLX_EXCLUDE = ":(exclude,glob)**/.sqlx/**"
local BIG_DIFF_MINIMUM_LINES = 5

local function git(args, options)
    local command = { "git" }
    vim.list_extend(command, args)
    return vim.system(command, options):wait()
end

local function split_nul(value)
    local fields = {}
    local start = 1

    while start <= #value do
        local finish = value:find("\0", start, true)
        if not finish then
            break
        end
        table.insert(fields, value:sub(start, finish - 1))
        start = finish + 1
    end

    return fields
end

local function open_diffview(rev, paths)
    local args = {}
    if rev then
        table.insert(args, rev)
    end

    table.insert(args, "--")
    if paths then
        vim.list_extend(args, paths)
    end
    table.insert(args, SQLX_EXCLUDE)

    local escaped = vim.tbl_map(vim.fn.fnameescape, args)
    vim.cmd("DiffviewOpen " .. table.concat(escaped, " "))
end

local function untracked_files()
    local result = git({
        "ls-files", "--others", "--exclude-standard", "-z", "--", SQLX_EXCLUDE,
    }, { text = false })

    if result.code ~= 0 then
        vim.notify("Could not find untracked files for diff", vim.log.levels.ERROR)
        return nil
    end

    return split_nul(result.stdout or "")
end

local function reset_intent_to_add(paths)
    if #paths == 0 then
        return
    end

    local args = { "reset", "--quiet", "--" }
    vim.list_extend(args, paths)
    git(args, { text = true })
end

-- Diffview does not include untracked files when comparing against a commit.
-- Mark them intent-to-add for the lifetime of the view, then restore the index.
local function open_with_untracked(rev, select_files)
    local untracked = untracked_files()
    if not untracked then
        return
    end

    if #untracked > 0 then
        local args = { "add", "--intent-to-add", "--" }
        vim.list_extend(args, untracked)
        local result = git(args, { text = true })
        if result.code ~= 0 then
            vim.notify("Could not include untracked files in diff", vim.log.levels.ERROR)
            return
        end
    end

    local selected = select_files and select_files(rev) or nil
    if select_files and (not selected or #selected == 0) then
        reset_intent_to_add(untracked)
        if selected then
            vim.notify(
                "No files have at least " .. BIG_DIFF_MINIMUM_LINES .. " substantive changed lines",
                vim.log.levels.INFO
            )
        end
        return
    end

    local cleanup_autocmd
    if #untracked > 0 then
        cleanup_autocmd = vim.api.nvim_create_autocmd("User", {
            pattern = "DiffviewViewClosed",
            once = true,
            callback = function()
                reset_intent_to_add(untracked)
            end,
        })
    end

    local ok, error_message = pcall(open_diffview, rev, selected)
    if not ok then
        if cleanup_autocmd then
            vim.api.nvim_del_autocmd(cleanup_autocmd)
        end
        reset_intent_to_add(untracked)
        vim.notify(error_message, vim.log.levels.ERROR)
    end
end

local function fork_point()
    local main_exists = git({
        "show-ref", "--verify", "--quiet", "refs/heads/main",
    }, { text = true }).code == 0

    local base_branch = main_exists and "main" or "origin/master"
    local result = git({ "merge-base", "HEAD", base_branch }, { text = true })
    local merge_base = vim.trim(result.stdout or "")

    if result.code ~= 0 or merge_base == "" then
        vim.notify("Could not determine merge base", vim.log.levels.ERROR)
        return nil
    end

    return merge_base
end

-- Git reports a replaced line as one deletion and one addition. Taking the
-- larger count approximates changed source lines without counting it twice.
-- Whitespace-only changes and pure file renames score zero.
local function substantially_changed_files(rev, minimum)
    local result = git({
        "diff", "--numstat", "-w", "--find-renames", "-z", rev, "--", SQLX_EXCLUDE,
    }, { text = false })

    if result.code ~= 0 then
        vim.notify("Could not calculate filtered diff", vim.log.levels.ERROR)
        return nil
    end

    local fields = split_nul(result.stdout or "")
    local paths = {}
    local seen = {}

    local function add(path)
        if path and path ~= "" and not seen[path] then
            seen[path] = true
            table.insert(paths, path)
        end
    end

    local i = 1
    while i <= #fields do
        local added, deleted, path = fields[i]:match("^([^\t]+)\t([^\t]+)\t(.*)$")
        if not added then
            break
        end

        local old_path
        if path == "" then
            old_path = fields[i + 1]
            path = fields[i + 2]
            i = i + 3
        else
            i = i + 1
        end

        local score
        if added == "-" or deleted == "-" then
            score = math.huge -- Always retain changed binary files.
        else
            score = math.max(tonumber(added), tonumber(deleted))
        end

        if score >= minimum then
            add(old_path)
            add(path)
        end
    end

    return paths
end

function M.open_fork_point()
    local merge_base = fork_point()
    if merge_base then
        open_with_untracked(merge_base)
    end
end

function M.open_big_diff()
    local merge_base = fork_point()
    if merge_base then
        open_with_untracked(merge_base, function(rev)
            return substantially_changed_files(rev, BIG_DIFF_MINIMUM_LINES)
        end)
    end
end

function M.open_latest()
    local current_result = git({ "rev-parse", "--abbrev-ref", "HEAD" }, { text = true })
    local current = vim.trim(current_result.stdout or "")
    if current_result.code ~= 0 or current == "" then
        vim.notify("Could not determine current branch", vim.log.levels.ERROR)
        return
    end

    -- Find the nearest ancestor also contained by another branch. The first
    -- boundary commit in topo order is the closest shared ancestor.
    local result = git({
        "rev-list", "--topo-order", "--boundary", "HEAD", "--not",
        "--exclude=" .. current, "--branches",
    }, { text = true })

    if result.code ~= 0 then
        vim.notify("Could not find parent branch for latest diff", vim.log.levels.ERROR)
        return
    end

    local target
    for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        if line:sub(1, 1) == "-" then
            target = vim.trim(line:sub(2))
            break
        end
    end

    if target and target ~= "" then
        open_with_untracked(target)
    else
        vim.notify("No parent branch found for latest diff", vim.log.levels.WARN)
    end
end

function M.open_head()
    open_diffview("HEAD")
end

function M.open_ancestor(count)
    assert(type(count) == "number" and count > 0 and count % 1 == 0, "count must be a positive integer")

    local rev = "HEAD~" .. count
    local result = git({ "rev-parse", "--verify", "--quiet", rev .. "^{commit}" }, { text = true })
    if result.code ~= 0 then
        vim.notify("Could not find " .. rev, vim.log.levels.WARN)
        return
    end

    open_with_untracked(rev)
end

function M.open_worktree()
    open_diffview(nil)
end

return M
