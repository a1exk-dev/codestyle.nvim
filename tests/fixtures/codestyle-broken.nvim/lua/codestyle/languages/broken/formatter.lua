-- The formatter of the fake broken plugin: one Block for the whole text, or
-- an error while `build.raise` is on.

local block = require('codestyle.block')

---@type codestyle.Formatter
return {
  build = function(ctx)
    if ctx.values.build.raise then
      error('the fake broken plugin raises on purpose')
    end
    return block.new({ node = ctx.root, children = {} })
  end,
  rules = {},
}
