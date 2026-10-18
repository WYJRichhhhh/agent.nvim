if vim.g.loaded_agent_nvim then
    return
end
vim.g.loaded_agent_nvim = true

local actions = {
    "open",
    "hide",
    "toggle",
    "focus",
    "start",
    "resume",
    "stop",
    "select",
    "status",
    "health",
    "help",
    "changes",
    "code",
    "diff",
    "filediff",
    "gitdiff",
    "follow",
    "pause",
    "turns",
    "next",
    "prev",
}
vim.api.nvim_create_user_command("Agent", function(args)
    local action, backend = args.fargs[1] or "focus", args.fargs[2]
    if
        not vim.tbl_contains(actions, action)
        or #args.fargs > 2
        or (backend and action ~= "start" and action ~= "open" and action ~= "resume")
    then
        vim.notify(
            "用法：:Agent [open|hide|toggle|focus|start|resume|stop|select|status|health|help|changes|code|diff|filediff|gitdiff|follow|pause|turns|next|prev] [backend]",
            vim.log.levels.WARN
        )
        return
    end
    local agent = require("agent")
    if action == "health" then
        vim.cmd.checkhealth("agent")
    elseif action == "status" then
        vim.print(agent.status())
    else
        agent[action](backend)
    end
end, {
    nargs = "*",
    desc = "管理常驻 AI CLI 会话",
    complete = function(lead, line)
        local words = vim.split(line, "%s+")
        local names = #words <= 2 and actions or vim.tbl_keys(require("agent.config").options.backends)
        table.sort(names)
        return vim.tbl_filter(function(value)
            return vim.startswith(value, lead)
        end, names)
    end,
})
