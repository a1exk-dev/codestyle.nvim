-- Test dependencies of the Core, pinned to commits (ADR-0017).
-- `tests/run.lua` clones each one into the gitignored `.tests/`.

---@class codestyle.test.Dep
---@field name string folder name under `.tests/`
---@field url string
---@field commit string

---@type codestyle.test.Dep[]
return {
  {
    name = 'mini.test',
    url = 'https://github.com/nvim-mini/mini.test',
    commit = '35c67cb7f2dc697ed0c7c06400fcf29a8a521d7d', -- v0.18.0
  },
  {
    name = 'snacks.nvim',
    url = 'https://github.com/folke/snacks.nvim',
    commit = 'e6fd58c82f2f3fcddd3fe81703d47d6d48fc7b9f', -- v2.31.0
  },
  {
    name = 'conform.nvim',
    url = 'https://github.com/stevearc/conform.nvim',
    commit = '3543d000dafbc41cc7761d860cfdb24e82154f75', -- v9.1.0
  },
}
