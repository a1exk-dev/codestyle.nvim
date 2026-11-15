-- The LSP access of Arrangement (ADR-0011, ADR-0002): `ctx.lsp(method, params)`
-- asks a client of the buffer synchronously, within one time budget per
-- format run. Plugins use it for parents in other files, the "overridden"
-- features. With no client, an unsupported method or a timeout, it returns
-- nil, and the run gives one warning.

local M = {}

--- Named seam (#50): the time budget of all LSP requests of one format run, in
--- milliseconds. It is not a user setting. The PHP map decides the value and
--- records it in ADR-0011; until then it is 1000, and a test pins it.
M.BUDGET_MS = 1000

--- Asks the LSP: the result of the request, or nil when there is none.
---@alias codestyle.Lsp fun(method: string, params: table): any

--- The LSP access of one format run.
---@param buf? integer the buffer whose clients answer; nil (the Preview) has none
---@param notices codestyle.Notice[] the run's notices, which get the warning
---@return fun(language: string): codestyle.Lsp
function M.new(buf, notices)
  local deadline ---@type number?

  ---@param language string
  ---@param method string
  ---@param reason string
  local function fail(language, method, reason)
    table.insert(notices, {
      level = vim.log.levels.WARN,
      scope = 'run',
      key = 'arrangement:lsp',
      message = ('Arrangement of "%s" needs the LSP (%s), but %s; "overridden" matches nothing'):format(
        language,
        method,
        reason
      ),
    })
  end

  return function(language)
    return function(method, params)
      local clients = buf and vim.lsp.get_clients({ bufnr = buf }) or {}
      if #clients == 0 then
        fail(language, method, 'no LSP client is attached to the buffer')
        return nil
      end
      local client = vim.iter(clients):find(function(candidate)
        return candidate:supports_method(method, buf)
      end)
      if not client then
        fail(language, method, 'no LSP client of the buffer supports it')
        return nil
      end
      local now = vim.uv.hrtime() / 1e6
      deadline = deadline or now + M.BUDGET_MS
      local left = math.floor(deadline - now)
      local response, problem
      if left > 0 then
        response, problem = client:request_sync(method, params, left, buf)
      end
      if not response then
        fail(
          language,
          method,
          (problem == nil or problem == 'timeout') and ('it gave no answer within %d ms'):format(M.BUDGET_MS)
            or tostring(problem)
        )
        return nil
      end
      if response.err then
        local method_not_found = -32601
        fail(
          language,
          method,
          response.err.code == method_not_found and 'no LSP client of the buffer supports it'
            or 'it answered with an error: ' .. tostring(response.err.message)
        )
        return nil
      end
      return response.result
    end
  end
end

return M
