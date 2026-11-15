# The Core chooses the plugin by override, then filetype, then PhpStorm's globs

The Core chooses the Language Plugin for a buffer in three steps, and stops at the first step that gives an answer. First the user's override: `vim.b.codestyle_language` for one buffer, else `setup{ filetypes = { htmldjango = 'twig', xml = false } }`, where `false` turns codestyle off for that filetype. Then the filetype: a spec that lists the buffer's filetype claims it. Only when no spec lists the filetype, or the filetype is empty, does the Core ask each spec's `match(buf)`. So the user's `:set ft=`, modeline or `vim.filetype.add` always wins, and `match(buf)` fills only the holes that #41 found: `.html` with Twig tags (`htmldjango`), `.inc` (`pov`), `.module` (`virata`), and names with no filetype such as `phpunit.xml.dist` and `*.es6`. Every first-party `match(buf)` accepts exactly the file name globs that PhpStorm assigns to its language (`data/catalog.json`), through the Core helper `require('codestyle').match_globs{ ... }`, so these buffers go where PhpStorm puts them ("How does the Core choose the Language Plugin and parser for a buffer?", #42, with the facts of #41).

The spec names its parsers as data: `parsers = { <filetype> = { <parser>, <fallback>, ... }, default = { ... } }`. The Core uses the first installed parser of the buffer's filetype key, else of `default`. For example, TypeScript has `typescriptreact = { 'tsx' }`, and JSON has `jsonc = { 'jsonc', 'json' }`, because nvim-treesitter `master` has a `jsonc` parser and `main` does not. The Core never asks `vim.treesitter.language.get_lang`, which without nvim-treesitter returns the filetype name itself.

## Considered Options

- **`match(buf)` before the filetype.** A plugin could keep a `.ts` file that Neovim calls `xml`, as PhpStorm does by name. Rejected: a plugin could override what the user set, and every `match` would run on every buffer.
- **PhpStorm's globs before the filetype.** Closest to PhpStorm, but it ignores the user's filetype for every named file.
- **No override.** Users would steer through the filetype, which also changes highlighting, LSP and other plugins.
- **On a conflict, the first spec on the runtimepath wins, or a spec `priority` wins.** Rejected: the winner would depend on plugin load order, or plugins would compete for priority values.
- **One Tree-sitter language per spec** (ADR-0007 before this ADR). It cannot serve `typescript` and `tsx`, or `jsonc` on both nvim-treesitter branches.
- **A `parser(buf)` function.** More flexible, but code that each plugin writes and tests. No v1 language needs it.
- **A cached choice per buffer.** Rejected: `match(buf)` can read content, which changes without an event.

## Consequences

- **Conflicts:** when two specs claim a buffer at the same step (both list the filetype, or two `match` return true), no plugin formats it. One WARN per filetype per session names both plugins and the `setup{ filetypes = ... }` line that picks one, and `:checkhealth codestyle` lists the conflict. First-party specs must not overlap. Their one shared glob, `*.php` and `*.blade.php`, never reaches `match`, because Neovim always gives `*.blade.php` the filetype `blade`.
- **Dotted filetypes:** for both the claim and the parser table, the Core tries the whole name, then the part before the first dot, as `get_lang` does. So `yaml.ansible` goes to the YAML plugin and `parsers.yaml`, unless a spec lists `yaml.ansible`.
- **No cache:** the Core chooses again at every format run. On `FileType`, it sets its `formatexpr` on a buffer that is now claimed and clears its own `formatexpr` on a buffer that is no longer claimed (ADR-0014).
- **Required table:** `parsers.default` is required, except in a spec whose `formatter.format` replaces the engine (Shell Script with `shfmt`, ADR-0002), which needs no parser. When no parser in the list is installed, ADR-0014's warning applies.
- **Preview:** the Preview parses and highlights its samples with `parsers.default`. This replaces ADR-0007's separate Tree-sitter language for the Preview.
- **Embed Points:** an Embed Point may name a key of the Embedded Language's parser table, such as `parser_key = 'typescriptreact'` for Vue `<script lang="tsx">`, else the Core uses `default` (ADR-0008). Parser names live only in the Embedded Language's spec.
- **Family maps decide** each spec's `filetypes` list (for example `javascriptreact`, `svg`, `zsh`, `automake`, `json5`), its parser table, and grammar shapes that differ between nvim-treesitter branches, such as Blade's, inside its builders (ADR-0002).
