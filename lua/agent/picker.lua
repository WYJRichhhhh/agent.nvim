local M = {}

-- Telescope is optional: terminal-only users retain Neovim's standard selector.
function M.select(entries, opts, callback)
    if opts.picker == "ui_select" then
        return vim.ui.select(entries, opts, callback)
    end
    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then
        return vim.ui.select(entries, opts, callback)
    end
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local conf = require("telescope.config").values
    vim.cmd.stopinsert()
    pickers
        .new({}, {
            prompt_title = opts.prompt,
            finder = finders.new_table({
                results = entries,
                entry_maker = function(entry)
                    local label = opts.format_item(entry)
                    return { value = entry, display = label, ordinal = label }
                end,
            }),
            sorter = conf.generic_sorter({}),
            previewer = previewers.new_buffer_previewer({
                title = "Agent diff",
                define_preview = function(self, entry)
                    vim.api.nvim_buf_set_lines(
                        self.state.bufnr,
                        0,
                        -1,
                        false,
                        vim.split(entry.value.diff, "\n", { plain = true })
                    )
                    vim.bo[self.state.bufnr].filetype = "diff"
                end,
            }),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    local selected = action_state.get_selected_entry()
                    actions.close(prompt_bufnr)
                    if selected then
                        vim.schedule(function()
                            callback(selected.value)
                        end)
                    end
                end)
                return true
            end,
        })
        :find()
end

return M
