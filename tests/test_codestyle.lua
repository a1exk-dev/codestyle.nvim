local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup()
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

T['api is the contract version 1'] = function()
  expect.equality(child.lua_get('require("codestyle").api'), 1)
end

return T
