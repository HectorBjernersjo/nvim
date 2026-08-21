local M = {}

local GIT_SQLX_EXCLUDE = ":(exclude,glob)**/.sqlx/**"
local JJ_SQLX_EXCLUDE = "~glob:**/.sqlx/**"
local BIG_DIFF_MINIMUM_LINES = 5
local NO_BIG_FILES = "No files have at least " .. BIG_DIFF_MINIMUM_LINES .. " substantive changed lines"

---@param args string[]
---@param options table?
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

--- Diffview picks the VCS adapter itself (jj first, see the plugin spec), so
--- `rev` must be a revision that adapter understands.
---@param rev string? # Revision to compare the working tree against; nil compares against the index
---@param paths string[] # Git pathspecs or jj filesets
local function open_diffview(rev, paths)
    local args = { "--" }
    vim.list_extend(args, paths)
    if rev then
        table.insert(args, 1, rev)
    end

    local escaped = vim.tbl_map(vim.fn.fnameescape, args)
    vim.cmd("DiffviewOpen " .. table.concat(escaped, " "))
end

-- Git reports a replaced line as one deletion and one addition. Taking the
-- larger count approximates changed source lines without counting it twice.
-- Whitespace-only changes and pure file renames score zero.
---@param repo Repo
---@param base string
---@param target string? # nil compares against the working tree
local function substantially_changed_files(repo, base, target)
    local args = { "diff", "--numstat", "-w", "--find-renames", "-z", base }
    if target then
        table.insert(args, target)
    end
    vim.list_extend(args, { "--", GIT_SQLX_EXCLUDE })

    local result = repo:git(args, { text = false })
    if result.code ~= 0 then
        return nil, "Could not calculate filtered diff"
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

        if score >= BIG_DIFF_MINIMUM_LINES then
            add(old_path)
            add(path)
        end
    end

    return paths
end

--- Both backends resolve a base revision and then hand it to Diffview.
--- Resolvers return the revision, or `nil` plus a message on failure. Git's
--- worktree base is `nil` on purpose: that compares against the index.
---@class Repo
---@field git fun(self, args: string[], options: table?): table
---@field worktree fun(self): string?, string?, number?
---@field head fun(self): string?, string?, number?
---@field fork_point fun(self): string?, string?, number?
---@field latest fun(self): string?, string?, number?
---@field ancestor fun(self, count: number): string?, string?, number?
---@field open fun(self, base: string?, opts: table)

--- Git: diffs run in the repository holding the current buffer, and the right
--- side of every diff is the working tree.
---@class GitRepo: Repo
local Git = {}
Git.__index = Git

function Git.detect()
    if git({ "rev-parse", "--show-toplevel" }, { text = true }).code ~= 0 then
        return nil
    end
    return setmetatable({}, Git)
end

function Git:git(args, options)
    return git(args, options)
end

function Git:worktree()
    return nil
end

function Git:head()
    return "HEAD"
end

function Git:fork_point()
    local main_exists = self:git({
        "show-ref", "--verify", "--quiet", "refs/heads/main",
    }, { text = true }).code == 0

    local base_branch = main_exists and "main" or "origin/master"
    local result = self:git({ "merge-base", "HEAD", base_branch }, { text = true })
    local merge_base = vim.trim(result.stdout or "")

    if result.code ~= 0 or merge_base == "" then
        return nil, "Could not determine merge base"
    end

    return merge_base
end

function Git:latest()
    local current_result = self:git({ "rev-parse", "--abbrev-ref", "HEAD" }, { text = true })
    local current = vim.trim(current_result.stdout or "")
    if current_result.code ~= 0 or current == "" then
        return nil, "Could not determine current branch"
    end

    -- Find the nearest ancestor also contained by another branch. The first
    -- boundary commit in topo order is the closest shared ancestor.
    local result = self:git({
        "rev-list", "--topo-order", "--boundary", "HEAD", "--not",
        "--exclude=" .. current, "--branches",
    }, { text = true })

    if result.code ~= 0 then
        return nil, "Could not find parent branch for latest diff"
    end

    for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        if line:sub(1, 1) == "-" then
            local target = vim.trim(line:sub(2))
            if target ~= "" then
                return target
            end
        end
    end

    return nil, "No parent branch found for latest diff", vim.log.levels.WARN
end

function Git:ancestor(count)
    local rev = "HEAD~" .. count
    local result = self:git({ "rev-parse", "--verify", "--quiet", rev .. "^{commit}" }, { text = true })
    if result.code ~= 0 then
        return nil, "Could not find " .. rev, vim.log.levels.WARN
    end

    return rev
end

function Git:untracked_files()
    local result = self:git({
        "ls-files", "--others", "--exclude-standard", "-z", "--", GIT_SQLX_EXCLUDE,
    }, { text = false })

    if result.code ~= 0 then
        return nil, "Could not find untracked files for diff"
    end

    return split_nul(result.stdout or "")
end

function Git:reset_intent_to_add(paths)
    if #paths == 0 then
        return
    end

    local args = { "reset", "--quiet", "--" }
    vim.list_extend(args, paths)
    self:git(args, { text = true })
end

function Git:open(base, opts)
    if not opts.untracked then
        local ok, error_message = pcall(open_diffview, base, { GIT_SQLX_EXCLUDE })
        if not ok then
            vim.notify(error_message, vim.log.levels.ERROR)
        end
        return
    end

    -- Diffview does not include untracked files when comparing against a
    -- commit. Mark them intent-to-add for the lifetime of the view, then
    -- restore the index.
    local untracked, err = self:untracked_files()
    if not untracked then
        vim.notify(err, vim.log.levels.ERROR)
        return
    end

    if #untracked > 0 then
        local args = { "add", "--intent-to-add", "--" }
        vim.list_extend(args, untracked)
        if self:git(args, { text = true }).code ~= 0 then
            vim.notify("Could not include untracked files in diff", vim.log.levels.ERROR)
            return
        end
    end

    local paths = { GIT_SQLX_EXCLUDE }
    if opts.select_files then
        paths, err = opts.select_files(self, base, nil)
        if not paths then
            self:reset_intent_to_add(untracked)
            vim.notify(err, vim.log.levels.ERROR)
            return
        end
        if #paths == 0 then
            self:reset_intent_to_add(untracked)
            vim.notify(NO_BIG_FILES, vim.log.levels.INFO)
            return
        end
    end

    local cleanup_autocmd
    if #untracked > 0 then
        cleanup_autocmd = vim.api.nvim_create_autocmd("User", {
            pattern = "DiffviewViewClosed",
            once = true,
            callback = function()
                self:reset_intent_to_add(untracked)
            end,
        })
    end

    local ok, error_message = pcall(open_diffview, base, paths)
    if not ok then
        if cleanup_autocmd then
            vim.api.nvim_del_autocmd(cleanup_autocmd)
        end
        self:reset_intent_to_add(untracked)
        vim.notify(error_message, vim.log.levels.ERROR)
    end
end

--- jj: every jj command snapshots the working copy into `@`, so there is no
--- index and no untracked files to special-case. Diffview's jj adapter diffs a
--- base revision against the files on disk; only the big-diff numstat still
--- goes through Git, straight against the repository backing jj's store.
---@class JjRepo: Repo
---@field git_dir string
local Jj = {}
Jj.__index = Jj

function Jj.detect()
    if vim.system({ "jj", "root" }, { text = true }):wait().code ~= 0 then
        return nil
    end

    local result = vim.system({ "jj", "git", "root" }, { text = true }):wait()
    if result.code ~= 0 then
        return nil, "This jj repo is not backed by Git: " .. vim.trim(result.stderr or "")
    end

    return setmetatable({ git_dir = vim.trim(result.stdout) }, Jj)
end

-- Both sides of a numstat are commits, so no work tree is needed. This is
-- what makes `jj workspace add` workspaces work: they have no `.git` of
-- their own.
function Jj:git(args, options)
    local command = { "--git-dir=" .. self.git_dir }
    vim.list_extend(command, args)
    return git(command, options)
end

--- Resolve a revset to a single commit id, which both Diffview and Git accept.
--- Snapshots the working copy first, so `@` always reflects what is on disk.
function Jj:rev(revset)
    local result = vim.system({
        "jj", "log", "--no-graph", "--color=never",
        "--revisions", revset, "--template", 'commit_id ++ "\n"',
    }, { text = true }):wait()

    if result.code ~= 0 then
        return nil, "Could not resolve jj revset '" .. revset .. "': " .. vim.trim(result.stderr or "")
    end

    local ids = vim.split(vim.trim(result.stdout or ""), "\n", { trimempty = true })
    if #ids == 0 then
        return nil, "jj revset '" .. revset .. "' matched no revisions", vim.log.levels.WARN
    end
    if #ids > 1 then
        return nil, "jj revset '" .. revset .. "' matched " .. #ids .. " revisions", vim.log.levels.WARN
    end

    return ids[1]
end

-- jj has no index, so "uncommitted changes" and "changes against the parent"
-- are the same diff: the working-copy commit against its parent.
function Jj:worktree()
    return self:rev("@-")
end

function Jj:head()
    return self:rev("@-")
end

-- The trunk is whichever of main/master, local or on origin, is newest. A local
-- main that has not been pushed for a while is ahead of main@origin, and diffing
-- against the remote would fold all of main's own commits into the feature.
-- present() makes the revset valid when a bookmark does not exist.
local TRUNK = "latest(present(main) | present(master) | present(main@origin) | present(master@origin) | trunk())"

-- A personal tweaks commit (bookmark "base") can sit between trunk and @
-- (merged into the working copy in HRM workspaces). Its changes are not part
-- of the work being diffed, so start from base when it is an ancestor of @,
-- otherwise from the trunk fork point as usual.
function Jj:fork_point()
    return self:rev("heads((present(base) & ::@) | fork_point(" .. TRUNK .. " | @))")
end

-- jj tracks no branch per workspace. The nearest bookmarked ancestor is the
-- closest equivalent of a parent branch: the last change that was named or
-- pushed.
-- The tweaks bookmark "base" is excluded — it names personal config, not a
-- parent branch, and would otherwise tie with real feature bookmarks for
-- nearest ancestor.
function Jj:latest()
    return self:rev("latest(heads(::@- & ::((bookmarks() | remote_bookmarks()) ~ present(base))))")
end

-- The working copy is a change of its own, so `count` dashes back covers the
-- last `count` changes, uncommitted work included.
function Jj:ancestor(count)
    return self:rev("@" .. string.rep("-", count))
end

function Jj:open(base, opts)
    local paths = { JJ_SQLX_EXCLUDE }
    if opts.select_files then
        local target, err = self:rev("@")
        if not target then
            vim.notify(err, vim.log.levels.ERROR)
            return
        end

        -- jj filesets union, so the exclude must not be added to a selection.
        paths, err = opts.select_files(self, base, target)
        if not paths then
            vim.notify(err, vim.log.levels.ERROR)
            return
        end
        if #paths == 0 then
            vim.notify(NO_BIG_FILES, vim.log.levels.INFO)
            return
        end
    end

    local ok, error_message = pcall(open_diffview, base, paths)
    if not ok then
        vim.notify(error_message, vim.log.levels.ERROR)
    end
end

-- jj first: a colocated repo is also a Git repo, and Diffview is configured
-- to prefer jj there too (see the plugin spec).
---@return Repo?
local function detect()
    local jj, err = Jj.detect()
    if jj then
        return jj
    end

    local repo = Git.detect()
    if repo then
        return repo
    end

    vim.notify(err or "Not inside a Git repository or jj workspace", vim.log.levels.ERROR)
    return nil
end

---@param resolve_base fun(repo: Repo): string?, string?, number?
---@param opts table? # untracked: include untracked files (Git only), select_files
local function open(resolve_base, opts)
    local repo = detect()
    if not repo then
        return
    end

    local base, err, level = resolve_base(repo)
    if err then
        vim.notify(err, level or vim.log.levels.ERROR)
        return
    end

    repo:open(base, opts or {})
end

function M.open_fork_point()
    open(function(repo) return repo:fork_point() end, { untracked = true })
end

function M.open_big_diff()
    open(function(repo) return repo:fork_point() end, {
        untracked = true,
        select_files = substantially_changed_files,
    })
end

function M.open_latest()
    open(function(repo) return repo:latest() end, { untracked = true })
end

function M.open_head()
    open(function(repo) return repo:head() end)
end

function M.open_worktree()
    open(function(repo) return repo:worktree() end)
end

function M.open_ancestor(count)
    assert(type(count) == "number" and count > 0 and count % 1 == 0, "count must be a positive integer")

    open(function(repo) return repo:ancestor(count) end, { untracked = true })
end

return M
