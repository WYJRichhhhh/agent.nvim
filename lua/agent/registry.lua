local M = {}

function M.register(name, backend)
    require("agent.config").validate_backend(name, backend)
    require("agent.config").options.backends[name] = vim.deepcopy(backend)
end

function M.available()
    local result = {}
    for name, backend in pairs(require("agent.config").options.backends) do
        if vim.fn.executable(backend.command[1]) == 1 then
            result[#result + 1] = name
        end
    end
    table.sort(result)
    return result
end

function M.get(name)
    return require("agent.config").options.backends[name]
end

return M
