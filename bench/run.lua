-- The bench script (ADR-0016): it formats the Preview sample of every Tab of
-- every installed Language Plugin with the default Code Style, and prints the
-- time of each step of the Format Run. It is run by hand, never in CI:
--
--   nvim -l bench/run.lua [plugin folder ...]
--
-- The folders are added to the runtimepath, for example `.` in a plugin repo.
-- Without `-u`, `nvim -l` loads no user config; give `-u <init>` to bench the
-- plugins that the config installs. Each sample runs `RUNS` times, and the
-- median time of each step is printed.

local RUNS = 5

local core = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))
vim.opt.runtimepath:prepend(core)
for _, dir in ipairs(_G.arg) do
  vim.opt.runtimepath:append(vim.fs.normalize(vim.fn.fnamemodify(dir, ':p')))
end

local core = require('codestyle.instance').new({
  notify = function(message)
    io.stdout:write(message, '\n')
  end,
})
local registry, format_run = core.registry, core.format_run
local code_style = require('codestyle.code_style')

---@param values number[]
---@return number
local function median(values)
  table.sort(values)
  return values[math.ceil(#values / 2)]
end

---@param spec codestyle.Spec
---@return string?
local function parser_of(spec)
  for _, parser in ipairs(spec.parsers.default or {}) do
    if vim.treesitter.language.add(parser) then
      return parser
    end
  end
end

local style = code_style.new({ version = 1, languages = {} }, registry)
for _, id in ipairs(code_style.used_languages(registry)) do
  local spec = registry.get(id) --[[@as codestyle.Spec]]
  local parser = parser_of(spec)
  for _, tab in ipairs(spec.tabs or {}) do
    if tab.sample and not parser then
      io.stdout:write(
        ('%s %s: no parser of %s is installed\n'):format(id, tab.name, table.concat(spec.parsers.default or {}, ', '))
      )
    elseif tab.sample then
      local steps, order = {}, {} ---@type table<string, number[]>, string[]
      local totals = {} ---@type number[]
      local failed ---@type string?
      for _ = 1, RUNS do
        local start = vim.uv.hrtime()
        local result, failure = format_run.run({
          lines = vim.deepcopy(tab.sample --[[@as string[] ]]),
          language = id,
          parser = parser --[[@as string]],
          code_style = style,
          timings = true,
        })
        table.insert(totals, (vim.uv.hrtime() - start) / 1e6)
        if not result then
          failed = (failure --[[@as codestyle.FormatFailure]]).message
          break
        end
        for _, timing in ipairs(result.timings or {}) do
          if not steps[timing.step] then
            steps[timing.step] = {}
            table.insert(order, timing.step)
          end
          table.insert(steps[timing.step], timing.ms)
        end
      end
      local label = ('%s %s'):format(id, tab.name)
      if failed then
        io.stdout:write(('%s: the Language Plugin failed: %s\n'):format(label, failed))
      else
        for _, step in ipairs(order) do
          io.stdout:write(('%-24s %-16s %8.3f ms\n'):format(label, step, median(steps[step])))
        end
        io.stdout:write(('%-24s %-16s %8.3f ms\n'):format(label, 'total', median(totals)))
      end
    end
  end
end
