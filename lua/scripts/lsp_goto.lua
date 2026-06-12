local M = {}

local function is_external(path)
    if not path or path == "" then return false end
    return path:match("/%.cargo/registry/") ~= nil
        or path:match("/%.cargo/git/") ~= nil
        or path:match("/%.rustup/toolchains/") ~= nil
end

local function jump_to(item)
    vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
    vim.api.nvim_win_set_cursor(0, { item.lnum or 1, (item.col or 1) - 1 })
end

local function on_list(opts)
    local items = opts.items or {}
    local locals, externals = {}, {}
    for _, item in ipairs(items) do
        if is_external(item.filename) then
            table.insert(externals, item)
        else
            table.insert(locals, item)
        end
    end
    local final = #locals > 0 and locals or externals
    if #final == 0 then
        vim.notify("No results", vim.log.levels.INFO)
    elseif #final == 1 then
        jump_to(final[1])
    else
        vim.fn.setqflist({}, " ", {
            title = opts.title or "LSP",
            items = final,
            context = opts.context,
        })
        if pcall(require, "snacks") and Snacks and Snacks.picker then
            Snacks.picker.qflist()
        else
            vim.cmd("copen")
        end
    end
end

function M.definition()
    vim.lsp.buf.definition({ on_list = on_list })
end

function M.type_definition()
    vim.lsp.buf.type_definition({ on_list = on_list })
end

return M
