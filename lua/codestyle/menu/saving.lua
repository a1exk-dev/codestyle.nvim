-- Saving the Menu's Draft (ADR-0001, ADR-0006): `<C-s>`, and the Save /
-- Discard / Cancel question when unsaved changes would be lost. Each save
-- tells the user where it wrote, or why it did not.

---@class codestyle.menu.Saving
---@field save fun(s: codestyle.menu.State): boolean writes the Draft to its file
--- Asks what to do with unsaved changes. `on_closed` runs when they are saved
--- or discarded, `on_cancel` on Cancel or a failed save.
---@field ask fun(s: codestyle.menu.State, on_closed: fun(), on_cancel: fun())

local M = {}

---@param deps { notices: codestyle.Notices, path_of: fun(s: codestyle.menu.State): string }
---@return codestyle.menu.Saving
function M.new(deps)
  ---@param s codestyle.menu.State
  ---@return boolean
  local function save(s)
    local ok, problem = s.draft.save()
    if ok then
      deps.notices.report(vim.log.levels.INFO, 'always', 'menu', 'saved ' .. deps.path_of(s))
    else
      deps.notices.report(
        vim.log.levels.ERROR,
        'always',
        'menu',
        ('%s was not saved: %s'):format(deps.path_of(s), problem)
      )
    end
    return ok
  end

  ---@type codestyle.menu.Saving
  return {
    save = save,
    ask = function(s, on_closed, on_cancel)
      vim.ui.select({ 'Save', 'Discard', 'Cancel' }, {
        prompt = ('The Draft has unsaved changes. Save them to %s?'):format(deps.path_of(s)),
      }, function(choice)
        if choice == 'Save' then
          if save(s) then
            on_closed()
          else
            on_cancel()
          end
        elseif choice == 'Discard' then
          s.draft.discard()
          on_closed()
        else
          on_cancel()
        end
      end)
    end,
  }
end

return M
