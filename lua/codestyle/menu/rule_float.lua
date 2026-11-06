-- The rule float of the Arrangement Tab (ADR-0012): one row per part of a
-- rule that the spec allows (Is, Is not, Name, Namespace, Alias, Order).
-- `<CR>` edits a row: Is and Is not open a `snacks.picker` multi-select of
-- the spec's tokens, leaving out the tokens that the other one holds; Name
-- and Namespace are `vim.ui.input` fields checked with `vim.regex`; Alias and
-- Order pick one item with `vim.ui.select`. `x` clears a row. A refused set
-- or regex changes nothing; a refused token set opens the picker again. Each
-- confirmed edit goes to `commit` at once. The buffer is `codestyle://rule`.

local arrangement = require('codestyle.arrangement')

local M = {}

---@alias codestyle.menu.RulePart 'is'|'is_not'|'name'|'namespace'|'alias'|'order'

local LABELS = {
  is = 'Is',
  is_not = 'Is not',
  name = 'Name',
  namespace = 'Namespace',
  alias = 'Alias',
  order = 'Order',
}

local ORDERS = { { id = 'keep', label = 'Keep order' }, { id = 'by_name', label = 'By name' } }

---@class codestyle.menu.RuleFloatOpts
---@field title string
---@field spec codestyle.ArrangementSpec
---@field rule codestyle.ArrangementRule the rule to edit; the float edits a copy
---@field alias_rule boolean an alias's rule, which has no Alias and no Order
---@field aliases string[] the names of the aliases a rule may use
---@field notices codestyle.Notices
---@field commit fun(rule: codestyle.ArrangementRule) takes each confirmed edit
---@field on_close fun(rule: codestyle.ArrangementRule) runs after the float closes, with the last rule

--- The parts of a rule that the spec allows.
---@param opts codestyle.menu.RuleFloatOpts
---@return codestyle.menu.RulePart[]
local function parts_of(opts)
  local parts = { 'is', 'is_not' } ---@type codestyle.menu.RulePart[]
  for _, key in ipairs({ 'name', 'namespace' }) do
    if opts.spec[key] then
      table.insert(parts, key)
    end
  end
  if not opts.alias_rule then
    vim.list_extend(parts, { 'alias', 'order' })
  end
  return parts
end

--- The tokens of a set that the spec marks as mutually exclusive.
---@param spec codestyle.ArrangementSpec
---@param tokens string[]
---@return string[]? the first clash
local function clash(spec, tokens)
  for _, set in ipairs(spec.exclusive or {}) do
    local found = vim.tbl_filter(function(token)
      return vim.list_contains(tokens, token)
    end, set)
    if #found > 1 then
      return found
    end
  end
end

---@param opts codestyle.menu.RuleFloatOpts
function M.open(opts)
  local rule = vim.deepcopy(opts.rule)
  local parts = parts_of(opts)
  local label_of = function(id)
    return (opts.spec.labels or {})[id] or id
  end

  ---@param level integer
  ---@param message string
  local function notify(level, message)
    opts.notices.report(level, 'always', 'menu', message)
  end

  ---@param part codestyle.menu.RulePart
  ---@return string
  local function value_text(part)
    local value = rule[part]
    if part == 'is' or part == 'is_not' then
      return table.concat(value or {}, ', ')
    elseif part == 'name' or part == 'namespace' then
      return value and ('/%s/'):format(value) or ''
    elseif part == 'order' then
      return value == 'by_name' and ORDERS[2].label or ORDERS[1].label
    end
    return value or ''
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_name(buf, 'codestyle://rule')

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local lines = vim.tbl_map(function(part)
      return ('%-10s %s'):format(LABELS[part], value_text(part))
    end, parts)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function commit()
    render()
    opts.commit(vim.deepcopy(rule))
  end

  local win ---@type snacks.win

  ---@return codestyle.menu.RulePart
  local function part_at_cursor()
    return parts[vim.api.nvim_win_get_cursor(win.win)[1]]
  end

  --- The picker of Is or Is not, preselected with `selected`.
  ---@param part 'is'|'is_not'
  ---@param selected string[]
  local function pick(part, selected)
    local other = rule[part == 'is' and 'is_not' or 'is'] or {}
    local items = {}
    for _, token in ipairs(vim.list_extend(vim.list_extend({}, opts.spec.types), opts.spec.modifiers or {})) do
      if not vim.list_contains(other, token) then
        table.insert(items, { text = token, label = label_of(token) })
      end
    end
    local preselected = vim.tbl_filter(function(item)
      return vim.list_contains(selected, item.text)
    end, items)
    require('snacks').picker({
      title = LABELS[part],
      items = items,
      format = 'text',
      layout = { preset = 'select' },
      -- The picker goes back to the rule float when it closes.
      main = { current = true },
      on_show = function(picker)
        picker.list:set_selected(preselected)
      end,
      confirm = function(picker)
        local tokens = vim.tbl_map(function(item)
          return item.text
        end, picker:selected({ fallback = false }))
        picker:close()
        local found = clash(opts.spec, tokens)
        if found then
          notify(
            vim.log.levels.WARN,
            ('%s: %s cannot be together in one rule'):format(LABELS[part], table.concat(found, ', '))
          )
          vim.schedule(function()
            pick(part, tokens)
          end)
          return
        end
        rule[part] = #tokens > 0 and tokens or nil
        commit()
      end,
    })
  end

  ---@param part 'name'|'namespace'
  local function input(part)
    vim.ui.input(
      { prompt = ('%s (a Vim regex; empty for none): '):format(LABELS[part]), default = rule[part] },
      function(text)
        if text == nil then
          return
        end
        if text == '' then
          rule[part] = nil
          commit()
          return
        end
        -- The regex alone first, so that the error names the user's text.
        local ok, problem = pcall(vim.regex, text)
        if ok then
          ok, problem = pcall(vim.regex, arrangement.pattern(text))
        end
        if not ok then
          local message = tostring(problem)
          notify(
            vim.log.levels.ERROR,
            ('%s: "%s" is not a valid Vim regex: %s'):format(LABELS[part], text, message:match('E%d+:.*') or message)
          )
          return
        end
        rule[part] = text
        commit()
      end
    )
  end

  local function edit()
    local part = part_at_cursor()
    if part == 'is' or part == 'is_not' then
      pick(part --[[@as 'is'|'is_not']], rule[part] or {})
    elseif part == 'name' or part == 'namespace' then
      input(part --[[@as 'name'|'namespace']])
    elseif part == 'alias' then
      local items = vim.list_extend({ '(none)' }, opts.aliases)
      vim.ui.select(items, { prompt = 'Alias' }, function(choice)
        if choice then
          rule.alias = choice ~= '(none)' and choice or nil
          commit()
        end
      end)
    elseif part == 'order' then
      vim.ui.select(ORDERS, {
        prompt = 'Order',
        format_item = function(order)
          return order.label
        end,
      }, function(order)
        if order then
          rule.order = order.id ~= 'keep' and order.id or nil
          commit()
        end
      end)
    end
  end

  render()
  local width = 50
  win = require('snacks').win({
    buf = buf,
    title = ' ' .. opts.title .. ' ',
    footer = ' <CR> edit · x clear · q close ',
    border = 'rounded',
    width = width,
    height = #parts,
    zindex = 100,
    backdrop = false,
    enter = true,
    wo = { number = false, relativenumber = false, signcolumn = 'no', cursorline = true, wrap = false },
    keys = {
      ['<CR>'] = { '<CR>', edit, mode = 'n', nowait = true },
      x = {
        'x',
        function()
          local part = part_at_cursor()
          if rule[part] ~= nil then
            rule[part] = nil
            commit()
          end
        end,
        mode = 'n',
        nowait = true,
      },
      q = { 'q', 'close', mode = 'n', nowait = true },
      ['<Esc>'] = { '<Esc>', 'close', mode = 'n', nowait = true },
    },
    on_close = function()
      opts.on_close(vim.deepcopy(rule))
    end,
  })
end

return M
