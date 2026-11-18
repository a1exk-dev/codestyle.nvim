# codestyle.nvim

PhpStorm's Code Style in Neovim: edit the Options of each language in a Menu with a live Preview, and format your buffers as PhpStorm's Reformat Code does.

<!-- The demo GIF of the Menu goes here (codestyle-home#67). -->

> [!NOTE]
> codestyle.nvim is in 0.x: a minor version can break your setup. See [Pin a version](#pin-a-version).

## Requirements

- Neovim 0.11 or later.
- [snacks.nvim](https://github.com/folke/snacks.nvim), which draws the Menu.
- The Tree-sitter parsers of the Language Plugins that you install. The [Language Plugins](#language-plugins) table lists them.
- [`shfmt`](https://github.com/mvdan/sh) on your `PATH` for Shell Script.

## Install

The Core formats no language on its own. Add one Language Plugin per language that you use, from the [Language Plugins](#language-plugins) table.

With [lazy.nvim](https://github.com/folke/lazy.nvim), or in `lua/plugins/` of LazyVim:

```lua
{
  'a1exk-dev/codestyle.nvim',
  dependencies = {
    'folke/snacks.nvim',
    -- 'a1exk-dev/codestyle-json.nvim', -- one line per language, see Language Plugins
  },
}
```

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({
  'https://github.com/a1exk-dev/codestyle.nvim',
  'https://github.com/folke/snacks.nvim',
  -- 'https://github.com/a1exk-dev/codestyle-json.nvim', -- one line per language, see Language Plugins
})
```

With another plugin manager: install the same repos, and put each Language Plugin on the `runtimepath`, as you put the Core. rocks.nvim users install them with [rocks-git.nvim](https://github.com/nvim-neorocks/rocks-git.nvim). No `setup()` call is needed.

## Pin a version

The specs above install the latest release, because `main` holds only released commits. To choose when a breaking minor version reaches you, pin a range on each repo:

- lazy.nvim: `version = '^0.1'` stays on 0.1.x. From 1.0, `version = '1.*'` stays on 1.x.
- `vim.pack`: `{ src = 'https://github.com/a1exk-dev/codestyle.nvim', version = vim.version.range('^0.1') }`, or `vim.version.range('1.*')` from 1.0.

Each release is a Git tag and a [GitHub release](https://github.com/a1exk-dev/codestyle.nvim/releases) with its notes. There are no pre-release tags.

## Language Plugins

| Language | Repo | Parsers |
| --- | --- | --- |
| _No Language Plugin is released yet._ | | |

Each Language Plugin has its own `:help codestyle-<id>`, such as `:help codestyle-json`, with its filetypes, parsers and Options.

## First run

1. Open a file of a language that you installed.
2. Format it with `<leader>cf`, or a range with `gq`.
3. Open the Menu with `:Codestyle`. Change an Option and watch the Preview. `<C-s>` saves, `g?` lists the keys.
4. Import PhpStorm's own Code Style with `i` in the Menu, or with `:Codestyle import path/to/Project.xml`.

## conform.nvim and LazyVim

The Core adds the formatter `codestyle` to conform.nvim. Add it for every filetype, because one language can span several filetypes:

```lua
require('conform').setup({
  formatters_by_ft = { ['*'] = { 'codestyle' } },
})
```

In LazyVim, put the same `formatters_by_ft` in the `opts` of `stevearc/conform.nvim`, so LazyVim's `<leader>cf` and its format on save use codestyle.nvim.

Without conform.nvim, format on save with one autocmd:

```lua
vim.api.nvim_create_autocmd('BufWritePre', {
  callback = function(args) require('codestyle').format({ buf = args.buf }) end,
})
```

## `:checkhealth codestyle`

Run `:checkhealth codestyle` to find a missing parser, two plugins that claim one buffer, or another formatter that changes what codestyle.nvim writes.

## Docs

- `:help codestyle` is the full reference: setup, commands, keys, the Menu, Scheme XML import, storage and Arrangement.
- Writing a Language Plugin: start from the [Language Plugin template](https://github.com/a1exk-dev/codestyle-language-template.nvim).
- License: [MIT](LICENSE).
