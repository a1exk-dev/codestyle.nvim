-- `:checkhealth codestyle` (ADR-0014, ADR-0015): for each open buffer that a
-- Language Plugin claims, it lists what makes the output differ or fail.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-parsers.nvim' } })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- The text of the `:checkhealth codestyle` report.
---@return string
local function health()
  child.cmd('checkhealth codestyle')
  return table.concat(child.api.nvim_buf_get_lines(0, 0, -1, true), '\n')
end

local has = MiniTest.new_expectation('report has text', function(text, report)
  return report:find(text, 1, true) ~= nil
end, function(text, report)
  return ('Text: %s\nReport:\n%s'):format(text, report)
end)

local has_not = MiniTest.new_expectation('report has not text', function(text, report)
  return report:find(text, 1, true) == nil
end, function(text, report)
  return ('Text: %s\nReport:\n%s'):format(text, report)
end)

T['a claimed buffer is reported as ready'] = function()
  child:open_buffer({ filetype = 'lua', lines = { 'x=1' }, name = 'ready.lua' })

  has('ready.lua (lua): codestyle-lua.nvim formats it with the parser "lua"', health())
end

T['an unclaimed buffer is not listed'] = function()
  child:open_buffer({ filetype = 'text', lines = { 'x=1' }, name = 'notes.txt' })

  has_not('notes.txt', health())
end

T['lists a missing parser'] = function()
  child:open_buffer({ filetype = 'noparser', lines = { 'x=1' }, name = 'a.noparser' })

  has(
    'a.noparser (noparser): codestyle-parsers.nvim has no Tree-sitter parser for this buffer; '
      .. 'install one of: no_such_parser_a, no_such_parser_b',
    health()
  )
end

T['lists a plugin conflict'] = function()
  child:teardown()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-lua-rival.nvim' } })
  child:open_buffer({ filetype = 'lua', lines = { 'x=1' }, name = 'both.lua' })

  has('claim the filetype "lua", so none formats it', health())
end

T['lists another conform formatter for the filetype'] = function()
  child.lua([[
    require('conform').setup({ formatters_by_ft = { lua = { 'stylua', 'codestyle' }, ['*'] = { 'trim_whitespace' } } })
    vim.api.nvim_exec_autocmds('User', { pattern = 'LazyLoad', data = 'conform.nvim' })
  ]])
  child:open_buffer({ filetype = 'lua', lines = { 'x=1' }, name = 'a.lua' })

  local report = health()

  has('a.lua (lua): conform.nvim also runs stylua, trim_whitespace on this buffer', report)
  has_not('runs stylua, trim_whitespace, codestyle', report)
end

T['lists an attached LSP client that can format'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1' }, name = 'a.lua' })
  child.lua(
    [[
      local buf = ...
      vim.lsp.start({
        name = 'fake_formatter',
        cmd = function()
          local closing = false
          return {
            request = function(method, _, callback)
              if method == 'initialize' then
                callback(nil, { capabilities = { documentFormattingProvider = true } })
              elseif method == 'shutdown' then
                callback(nil, nil)
              end
              return true, 1
            end,
            notify = function() return true end,
            is_closing = function() return closing end,
            terminate = function() closing = true end,
          }
        end,
      }, { bufnr = buf })
      vim.wait(1000, function()
        return #vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/formatting' }) > 0
      end)
    ]],
    { buf }
  )

  has('a.lua (lua): the LSP client fake_formatter can format this buffer', health())
end

T['lists editorconfig trim when Keep indents on empty lines is on'] = function()
  local indents = { version = 1, languages = { lua = { indent = { keep_on_empty_lines = true } } } }
  child:write_global(indents)
  child:write_file(child.paths.repo .. '/.editorconfig', 'root = true\n[*]\ntrim_trailing_whitespace = true\n')
  child:open_buffer({ filetype = 'lua', lines = { 'x=1' }, name = child.paths.repo .. '/a.lua' })

  has(
    'a.lua (lua): editorconfig trim_trailing_whitespace removes the indents that '
      .. '"Keep indents on empty lines" keeps, when the file is saved',
    health()
  )
end

T['editorconfig trim is fine when Keep indents on empty lines is off'] = function()
  child:write_file(child.paths.repo .. '/.editorconfig', 'root = true\n[*]\ntrim_trailing_whitespace = true\n')
  child:open_buffer({ filetype = 'lua', lines = { 'x=1' }, name = child.paths.repo .. '/a.lua' })

  has_not('editorconfig', health())
end

return T
