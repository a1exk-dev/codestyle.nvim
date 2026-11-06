-- The editors of the Arrangement Tab (ADR-0012): they turn a key on a row of
-- the Tab into a Draft operation. Every confirmed edit writes the whole
-- Arrangement that formatting uses, with the edit, as one undo step; so an
-- invalid stored Arrangement is replaced by the first edit, and `X` removes
-- the stored value. A new rule reaches the Draft with its first condition: a
-- new rule closed with none is dropped and leaves no undo step.

local arrangement = require('codestyle.arrangement')
local float = require('codestyle.menu.float')
local rows = require('codestyle.menu.arrangement_rows')
local rule_float = require('codestyle.menu.rule_float')
local shape = require('codestyle.menu.arrangement_shape')

local M = {}

---@alias codestyle.menu.ArrangementAction
---| codestyle.menu.Action
---| 'reset_all' `X`
---| 'add_slot' `o`: a rule in a new Slot below, or a new alias
---| 'add_rule' `a`: a rule in the Slot under the cursor
---| 'down' `J`
---| 'up' `K`
---| 'slot_down' `gJ`
---| 'slot_up' `gK`
---| 'delete' `dd`
---| 'rename' `r`

--- The language whose Arrangement an action edits.
---@class codestyle.menu.ArrangementTarget
---@field draft codestyle.Draft
---@field language string
---@field spec codestyle.ArrangementSpec

---@class codestyle.menu.ArrangementEdit
--- Acts on a row; returns the row the cursor should go to after a move.
---@field act fun(target: codestyle.menu.ArrangementTarget, item: codestyle.menu.ArrangementItem, action: codestyle.menu.ArrangementAction): codestyle.menu.ArrangementItem?

--- The Arrangement that formatting uses now, and the bad part of an invalid stored one.
---@param target codestyle.menu.ArrangementTarget
---@return codestyle.Arrangement
---@return codestyle.ArrangementProblem?
function M.current(target)
  local stored = (target.draft.code_style().raw().languages or {})[target.language]
  return arrangement.validate(target.spec, type(stored) == 'table' and stored.arrangement or nil)
end

---@param deps { notices: codestyle.Notices, on_float_close: fun() }
---@return codestyle.menu.ArrangementEdit
function M.new(deps)
  ---@param level integer
  ---@param message string
  local function notify(level, message)
    deps.notices.report(level, 'always', 'menu', message)
  end

  --- Writes an Arrangement to the Draft when it differs from the current one.
  ---@param target codestyle.menu.ArrangementTarget
  ---@param new? codestyle.Arrangement
  ---@return boolean written
  local function write(target, new)
    if not new or vim.deep_equal(new, (M.current(target))) then
      return false
    end
    target.draft.set_arrangement(target.language, new)
    return true
  end

  local open_alias ---@type fun(target: codestyle.menu.ArrangementTarget, name: string)

  --- Opens the rule float on a rule, or on a new rule with `insert`.
  ---@param target codestyle.menu.ArrangementTarget
  ---@param place codestyle.menu.RulePlace
  ---@param insert? 'rule'|'slot'|'alias'
  ---@param on_close fun()
  local function edit_rule(target, place, insert, on_close)
    local current = M.current(target)
    local pending = insert
    local title = place.alias and ('Alias %s, rule %d'):format(place.alias, place.rule)
      or ('Slot %d, rule %d'):format(place.slot, place.rule)
    rule_float.open({
      title = title,
      spec = target.spec,
      rule = pending and {} or assert(shape.rule(current, place)),
      alias_rule = place.alias ~= nil,
      aliases = shape.alias_names(current),
      notices = deps.notices,
      commit = function(rule)
        if pending and not shape.has_condition(rule) then
          return
        end
        local now = M.current(target)
        write(target, shape.put(now, place, rule, pending))
        pending = nil
      end,
      on_close = function(rule)
        if not pending and not shape.has_condition(rule) then
          -- A rule with no condition would take every entry.
          if write(target, shape.delete(M.current(target), place)) then
            notify(vim.log.levels.INFO, 'a rule with no condition matches every entry, so it is dropped')
          end
        end
        on_close()
      end,
    })
  end

  ---@param target codestyle.menu.ArrangementTarget
  ---@param prompt string
  ---@param default? string
  ---@param on_name fun(name: string)
  local function ask_alias_name(target, prompt, default, on_name)
    vim.ui.input({ prompt = prompt, default = default }, function(name)
      name = name and vim.trim(name)
      if not name or name == '' or name == default then
        return
      end
      if M.current(target).aliases[name] then
        notify(vim.log.levels.WARN, ('an alias "%s" exists already; an alias needs a name of its own'):format(name))
        return
      end
      on_name(name)
    end)
  end

  ---@param target codestyle.menu.ArrangementTarget
  local function add_alias(target)
    ask_alias_name(target, 'New alias: ', nil, function(name)
      edit_rule(target, { alias = name, rule = 1 }, 'alias', deps.on_float_close)
    end)
  end

  --- The float of an alias's rules, with the keys of the Slot rows.
  ---@param target codestyle.menu.ArrangementTarget
  ---@param name string
  open_alias = function(target, name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.api.nvim_buf_set_name(buf, 'codestyle://alias')
    local win ---@type snacks.win

    local function render()
      local rules = M.current(target).aliases[name] or {}
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.tbl_map(shape.summary, rules))
      vim.bo[buf].modifiable = false
    end
    local unsubscribe = target.draft.subscribe(render)
    render()

    ---@return codestyle.menu.RulePlace
    local function place()
      return { alias = name, rule = vim.api.nvim_win_get_cursor(win.win)[1] }
    end
    local function back()
      if win:win_valid() then
        vim.api.nvim_set_current_win(win.win)
      end
    end
    ---@param delta 1|-1
    local function move(delta)
      local new, moved = shape.move(M.current(target), place(), delta)
      if write(target, new) and moved then
        vim.api.nvim_win_set_cursor(win.win, { moved.rule, 0 })
      end
    end

    local function key(lhs, fn)
      return { lhs, fn, mode = 'n', nowait = true }
    end
    win = require('snacks').win({
      buf = buf,
      title = (' Alias %s '):format(name),
      footer = ' <CR> edit · o add · J/K move · dd delete · q close ',
      border = 'rounded',
      width = 60,
      height = math.max(3, #(M.current(target).aliases[name] or {})),
      zindex = 90,
      backdrop = false,
      enter = true,
      wo = { number = false, relativenumber = false, signcolumn = 'no', cursorline = true, wrap = false },
      keys = {
        ['<CR>'] = key('<CR>', function()
          edit_rule(target, place(), nil, back)
        end),
        o = key('o', function()
          local at = place()
          edit_rule(target, { alias = name, rule = at.rule + 1 }, 'rule', back)
        end),
        J = key('J', function()
          move(1)
        end),
        K = key('K', function()
          move(-1)
        end),
        dd = key('dd', function()
          if not write(target, shape.delete(M.current(target), place())) then
            notify(
              vim.log.levels.WARN,
              ('the alias "%s" needs a rule; dd on its row in the Tab deletes the alias'):format(name)
            )
          end
        end),
        x = key('x', function()
          notify(vim.log.levels.INFO, 'a rule has no default of its own; X in the Tab resets the whole Arrangement')
        end),
        q = key('q', 'close'),
        ['<Esc>'] = key('<Esc>', 'close'),
      },
      on_close = function()
        unsubscribe()
        deps.on_float_close()
      end,
    })
  end

  --- The Keep-Together list with a kind turned on or off, or its order set.
  ---@param current codestyle.Arrangement
  ---@param kind string
  ---@param keep? codestyle.KeepTogether nil turns the kind off
  ---@param at? integer where a kind that was off goes; default the end
  ---@return codestyle.Arrangement
  local function with_keep(current, kind, keep, at)
    local new = vim.deepcopy(current)
    for index, existing in ipairs(new.keep_together) do
      if existing.kind == kind then
        if keep then
          new.keep_together[index] = keep
        else
          table.remove(new.keep_together, index)
        end
        return new
      end
    end
    if keep then
      table.insert(new.keep_together, math.min(at or math.huge, #new.keep_together + 1), keep)
    end
    return new
  end

  ---@param target codestyle.menu.ArrangementTarget
  ---@param current codestyle.Arrangement
  ---@param kind string
  ---@param action codestyle.menu.ArrangementAction
  local function act_keep(target, current, kind, action)
    local orders = target.spec.keep_together[kind]
    local keep = rows.keep_of(current, kind)
    if action == 'reset' then
      local default = arrangement.validate(target.spec, nil)
      for index, default_keep in ipairs(default.keep_together) do
        if default_keep.kind == kind then
          write(target, with_keep(current, kind, default_keep, index))
          return
        end
      end
      write(target, with_keep(current, kind, nil))
    elseif action == 'toggle' or (action == 'edit' and #orders == 1) then
      write(target, with_keep(current, kind, not keep and { kind = kind, order = orders[1] } or nil))
    elseif action == 'edit' then
      vim.ui.select(orders, {
        prompt = rows.label(target.spec, kind),
        format_item = function(order)
          return rows.label(target.spec, order)
        end,
      }, function(order)
        if order then
          write(target, with_keep(M.current(target), kind, { kind = kind, order = order }))
        end
      end)
    elseif action == 'next' or action == 'prev' then
      -- A kind that is off shows its first order: the step goes from there and turns it on.
      local index = 1
      for i, order in ipairs(orders) do
        if keep and keep.order == order then
          index = i
        end
      end
      local order = orders[(index - 1 + (action == 'prev' and -1 or 1)) % #orders + 1]
      write(target, with_keep(current, kind, { kind = kind, order = order }))
    end
  end

  ---@param target codestyle.menu.ArrangementTarget
  ---@param current codestyle.Arrangement
  ---@param kind string
  ---@param action codestyle.menu.ArrangementAction
  local function act_sort(target, current, kind, action)
    local sort = assert(shape.read_sort(current))
    if action == 'reset' then
      local default = arrangement.validate(target.spec, nil)
      write(target, vim.tbl_extend('force', current, { slots = default.slots }))
      return
    end
    ---@param order 'by_name'|'custom'
    local function set_order(order)
      local names = order == 'custom' and (sort.names or target.spec.custom_order or {}) or nil
      write(target, shape.write_sort(current, { sort = true, order = order, names = names }))
    end
    if kind == 'sort' then
      write(target, shape.write_sort(current, { sort = not sort.sort, order = 'by_name' }))
    elseif kind == 'sort_order' and action == 'edit' then
      vim.ui.select(rows.SORT_ORDERS, {
        prompt = 'Order',
        format_item = function(order)
          return order.label
        end,
      }, function(order)
        if order then
          current = M.current(target)
          set_order(order.id)
        end
      end)
    elseif kind == 'sort_order' then
      set_order(sort.order == 'by_name' and 'custom' or 'by_name')
    elseif kind == 'custom_order' and action == 'edit' then
      float.order({
        title = 'Custom order',
        lines = vim.deepcopy(sort.names or {}),
        editable = true,
        apply = function(names)
          if #names == 0 then
            notify(vim.log.levels.WARN, 'Custom order: the list needs a name; turn sorting off instead')
            return false
          end
          write(target, shape.write_sort(M.current(target), { sort = true, order = 'custom', names = names }))
          return true
        end,
        on_close = deps.on_float_close,
      })
    end
  end

  ---@type codestyle.menu.ArrangementEdit
  return {
    act = function(target, item, action)
      local current = M.current(target)
      local kind = item.kind
      if action == 'reset_all' then
        target.draft.reset_arrangement(target.language)
        return
      end
      if kind == 'enabled' then
        if action == 'reset' then
          write(target, vim.tbl_extend('force', current, { enabled = arrangement.validate(target.spec, nil).enabled }))
        elseif vim.list_contains({ 'toggle', 'edit', 'next', 'prev' }, action) then
          write(target, vim.tbl_extend('force', current, { enabled = not current.enabled }))
        end
      elseif kind == 'keep' then
        act_keep(target, current, assert(item.keep), action)
      elseif kind == 'sort' or kind == 'sort_order' or kind == 'custom_order' then
        act_sort(target, current, kind, action)
      elseif kind == 'rule' then
        local place = { slot = item.slot, rule = item.rule }
        if action == 'edit' then
          edit_rule(target, place, nil, deps.on_float_close)
        elseif action == 'reset' then
          notify(vim.log.levels.INFO, 'a rule has no default of its own; X resets the whole Arrangement')
        elseif action == 'add_slot' then
          edit_rule(target, { slot = item.slot + 1, rule = 1 }, 'slot', deps.on_float_close)
        elseif action == 'add_rule' then
          edit_rule(target, { slot = item.slot, rule = item.rule + 1 }, 'rule', deps.on_float_close)
        elseif action == 'delete' then
          write(target, shape.delete(current, place))
        elseif action == 'down' or action == 'up' or action == 'slot_down' or action == 'slot_up' then
          local delta = (action == 'down' or action == 'slot_down') and 1 or -1
          local move = (action == 'down' or action == 'up') and shape.move or shape.move_slot
          local new, moved = move(current, place, delta)
          if moved and write(target, new) then
            return { kind = 'rule', slot = moved.slot, rule = moved.rule }
          end
        end
      elseif kind == 'slots' then
        if action == 'add_slot' or action == 'add_rule' then
          edit_rule(target, { slot = 1, rule = 1 }, 'slot', deps.on_float_close)
        end
      elseif kind == 'aliases' then
        if action == 'add_slot' then
          add_alias(target)
        end
      elseif kind == 'alias' then
        local name = assert(item.alias)
        if action == 'edit' then
          open_alias(target, name)
        elseif action == 'add_slot' then
          add_alias(target)
        elseif action == 'rename' then
          ask_alias_name(target, ('Rename the alias "%s": '):format(name), name, function(to)
            write(target, shape.rename_alias(M.current(target), name, to))
          end)
        elseif action == 'delete' then
          local users = shape.alias_users(current, name)
          if #users > 0 then
            notify(
              vim.log.levels.WARN,
              ('the alias "%s" is used by the rules of Slot %s; change them first'):format(
                name,
                table.concat(users, ', ')
              )
            )
          else
            local new = vim.deepcopy(current)
            new.aliases[name] = nil
            write(target, new)
          end
        elseif action == 'reset' then
          notify(vim.log.levels.INFO, 'an alias has no default of its own; X resets the whole Arrangement')
        end
      end
    end,
  }
end

return M
