# Neovim UI patterns for the Menu and its live Preview

Research for [#7](https://github.com/a1exk-dev/codestyle.nvim/issues/7) (map: [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)).
Feeds the Menu prototype ticket, [#11](https://github.com/a1exk-dev/codestyle.nvim/issues/11), which decides the Neovim baseline and the UI dependencies.

Terms follow `GLOSSARY.md`: Menu, Tab, Option, Preview, Language Plugin, Core.

## Answer

- **Use three windows, and give each one a single scratch buffer that we render from a view model. Do not use one window per widget.** The panes are the language list, the Option pane with its Tab strip, and the Preview. Each buffer is `buftype=nofile`, `modifiable=false`, `winfixbuf`. On each change, we re-render the whole buffer: real text for the labels, extmarks for the highlights and the inline values, and a row→Option index for the keymaps. lazy.nvim, mason.nvim and neogit all build their UIs this way with no UI dependency ([L3], [L4], [M2], [G3]). The largest Tab in the Research Corpus, PHP "Wrapping and Braces", has 98 Option rows. A scrolling buffer handles that. A layout of windows, one per widget (nui-components), cannot scroll ([NC2]).
- **Layout: open the Menu in its own tabpage with normal splits, or in a float layout.** Both are proven. Splits get resizing, `<C-w>` navigation and mouse focus from Neovim itself, and need no layout code. Floats look like PhpStorm's dialog, but every float plugin has to re-run its layout on `VimResized` (lazy, mason, telescope, snacks) and on `WinResized` (snacks) ([L2], [M3], [T4], [S4], [S6]). The prototype should try both. If we choose floats, snacks.nvim's `snacks.layout` is the only surveyed library that handles nested boxes, splits and both resize events.
- **Widgets map onto Neovim idioms, so we need no widget library.**
  - Checkbox / radio: a `[x]` / `(•)` text row, toggled with `<Space>`/`<CR>`/click.
  - Combo / wrap combo: an inline `[a|b|c]` cycle, as in neogit popups ([G1]), plus `<CR>` → `vim.ui.select` for long lists.
  - Int field / text field: `vim.ui.input` with min/max validation ([N16]).
  - List editor (PHPDoc tag order): a sub-buffer with one item per line.
  - Group: a collapsible header row.

  `vim.ui.select` and `vim.ui.input` route to the picker that the user already has (snacks, fzf-lua, telescope-ui-select) ([S9], [S10], [F2]).
- **Preview highlighting:** use a scratch buffer and call `vim.treesitter.start(buf, lang)`. If no parser is installed, fall back to `vim.bo[buf].syntax = ft`. Do not set the real `filetype`, so that LSP clients and ftplugins do not attach. snacks, telescope and fzf-lua all use this pattern ([S7], [T2], [F1]). Neovim bundles only the C, Diff, Lua, Markdown, Vimscript and Vimdoc parsers ([N12]). For PHP and most corpus languages, the Preview therefore uses the Vim syntax files that Neovim ships, unless the user has installed a parser.
- **Mouse:** Neovim enables `mouse=nvi` by default since 0.8 ([R8a]). A buffer-local `<LeftMouse>` mapping plus `getmousepos()` gives clicks on Option rows. A `'winbar'` `%@…@` label gives clickable Tabs ([N9]). Do not turn on `'mousemoveevent'`. It is a global option that can abort pending mappings ([N10]), and volt sets it globally ([V1]).
- **Minimum Neovim:** the pattern above runs on **0.10**: inline virtual text, `nvim_open_win` splits, `winfixbuf`, float footers ([N20]). **0.11** adds the float `mouse` field, `eol_right_align` virtual text, and the global `'winborder'`. If we support 0.11, we must pass `border` explicitly ([N21]). Current stable is 0.12.6 ([R12]). Our own floor would be lower than telescope's (0.11) and the same as mason's and neogit's (0.10).
- **Dependencies: none are needed.** snacks.nvim is the only optional dependency worth its cost, and only if we choose floats. nui.nvim saves little: its `Layout` does not resize by itself. nui-components and volt do not fit (one window per widget; content drawn only as virtual text) ([NC1], [V2]).

## 1. What the Menu must show

From the PhpStorm screenshots (`screenshots/php/02-spaces-1.png`, `03-wrapping-and-braces-1.png`) and `data/ui-structure.json` in the Research Corpus:

- **Layout**: a settings tree on the left (here, the language list), a Tab strip ("Tabs and Indents", "Spaces", "Wrapping and Braces", …) and a "Set from…" link at the top, then an Option tree in the middle, and the Preview on the right. The Preview has syntax highlighting and visible whitespace.
- **Control kinds** in `ui-structure.json` (count of Options over 25 language pages): `checkbox` 595, `combo` 143, `group` 106, `int_field` 83, `wrap_combo` 57 (a combo in a group header row, with child checkboxes), `text_field` 25, `checkbox+radio` 20, `radio` 12, `list_field` 11 (for example the PHPDoc tag order, edited with + / − / up / down).
- **Tab kinds**: `option_tree` 27, `custom_panel` 28, `indent_options_editor` 19, `blank_lines_form` 10, `arrangement` 7.
- **Size**: the largest Tabs are PHP "Wrapping and Braces" (98 Option rows), PHP "Spaces" (80), and TypeScript "Wrapping and Braces" (78). The Option pane therefore must scroll.
- **Dependencies between Options**: some controls are enabled only when another control is set. For example, "Smart tabs" is enabled only when "Use tab character" is set (`dependencies` in "Tabs and Indents"). The Menu must show a disabled state.

## 2. Survey of existing plugins

### lazy.nvim — single float, text builder, full re-render

- Requires Neovim ≥ 0.8 ([L1]).
- **Window**: one float with `relative="editor"`, a size given as a fraction of the editor, and an optional dim backdrop. The backdrop is a second, unfocusable float with `winblend` ([L2]).
- **Resize**: a `VimResized` autocmd recomputes the layout, calls `nvim_win_set_config`, and fires `User LazyFloatResized`, which triggers a re-render ([L2], [L5]).
- **Rendering**: a `Text` builder collects segments of `{str, hl}`. It writes all lines with `nvim_buf_set_lines`, then adds one extmark (`hl_group`, `end_col`) per segment ([L3]).
- **Updates**: each update rebuilds everything. It sets `modifiable=true`, renders, restores the view with `winsaveview`/`winrestview` inside `nvim_win_call`, then sets `modifiable=false` again ([L4]). Updates are throttled to 30 per second ([L5]).
- **Row → item**: the renderer records `locations` (`from`/`to` rows per plugin). `get_plugin(row)` maps the cursor row back to the item ([L4]).
- **Tabs**: a "pills" row of buttons at the top, one per mode, each with its key ("Install (I)"). The active mode has its own highlight ([L4]).
- **Keymaps**: buffer-local, `nowait=true` ([L2]). Next/prev item jumps between the `locations` rows ([L5]).
- **Mouse**: none.

### mason.nvim — declarative node tree, keybinds bound to lines

- Requires Neovim ≥ 0.10 ([M1]).
- `mason-core/ui` (826 lines) is a small React-style framework:
  - **Nodes**: `Node`, `HlTextNode`, `VirtualTextNode`, `DiagnosticsNode`, `CascadingStyleNode` (indent, center), `Keybind`, `StickyCursor`, `When`, `Table` ([M2]).
  - **Render**: a `view(state)` function renders the node tree to lines, highlights, virtual text, diagnostics and per-line keybinds ([M3]).
- **State**: a state container calls the view again on each mutation. Updates are coalesced with `vim.schedule` ("debounced") ([M3], [M4]).
- **Keymaps**: a key is mapped once per buffer. When pressed, it dispatches to the handler that is registered for the **cursor line**, then to the global handler ([M3]). This is the same idea as "the Option under the cursor reacts to `<Space>`".
- **Sticky cursor**: after a re-render, the cursor is moved back to the line with the same `StickyCursor` id. The cursor therefore stays on the same item when the lines above it change ([M3]).
- **Tabs**: the global keybinds `1`…`5` switch the view ("All", "LSP", "DAP", …) ([M5]).
- **Dropdown**: the language filter uses `vim.ui.select` ([M5]).
- **Resize**: `VimResized` redraws and calls `nvim_win_set_config` again ([M3]).
- **Mouse**: none.

### neogit — component tree and transient-style "popups" with options

- Requires Neovim ≥ 0.10 ([G0]).
- **Renderer**: `lib/ui` renders a component tree into one buffer. It keeps a `RendererIndex` (line → components) and a fold state, and restores cursor and top line after each update ([G3]).
- **Popups**: neogit's popups are the closest surveyed analogue to a settings form. They have switches, options with values, and config entries:
  - A **config with fixed choices** renders as `[a|b|c]` with the active choice highlighted. A key press cycles to the next choice in place ([G1], [G2]).
  - An option with `choices` opens a fuzzy finder. A free-text value goes through `vim.ui.input`, wrapped as an async call ([G2], [G4]).

### nui.nvim — component primitives

- Requires Neovim ≥ 0.5 ([NU1]). About 6.9k lines of Lua.
- **Components**: `Popup` (float), `Split`, `Layout` (nested `Layout.Box` rows and columns of popups or splits), `Input`, `Menu`, `Tree`, `Line`/`Text` (highlighted text builders), `Table` ([NU1]).
- **Input**: a popup with `buftype=prompt` (`prompt_setprompt`, `startinsert!`) and `on_change`/`on_submit` callbacks ([NU2]).
- **Resize**: `Layout:update()` re-runs the layout ([NU3]). The library has no `VimResized` handler of its own, so the caller must call `update()` (only `nui/utils/autocmd.lua` names the event).

### nui-components.nvim — form library on top of nui

- Has form widgets: `checkbox`, `select`, `text_input`, `tabs`/`tab`, `button`, `slider`, `form` with validators, plus reactive signals ([NC1]).
- **Every component is a nui `Popup`**, so it is one floating window per widget. The renderer lays them out with `nui.layout` and moves focus between windows with `<Tab>`/`<S-Tab>` ([NC1], [NC2]).
- The library has no scrolling for a layout of components (only the `tree` and `buffer` components scroll inside their own window) ([NC2]). For a Tab with ~100 Options, this means ~100 floats and no way to scroll the form.
- **Maintenance**: the last push was 2025-03-15 ([NC3]), about 19 months before this research.

### snacks.nvim — window and layout primitives, pickers

- Requires Neovim ≥ 0.9.4 ([S1]). About 37k lines in total, but `Snacks.<module>` loads each module only when it is first used ([S2]). `snacks.win` + `snacks.layout` together have 1.9k lines.
- **`snacks.win`**:
  - One API for `position = "float"|"bottom"|"top"|"left"|"right"|"current"`.
  - Options `minimal`, `backdrop`, `fixbuf` (keeps other buffers out of the window), `resize`, buffer-local `keys`, and footer keys ([S3]).
  - Calls `on_resize` on `VimResized`, and reacts to `WinResized` ([S4]).
- **`snacks.layout`**:
  - Nested `box = "horizontal"|"vertical"` trees of windows, as floats or as a split layout. A split layout is wrapped in a box, because a plain split cannot have borders or titles ([S5]).
  - Re-runs the layout on `VimResized`, and on `WinResized` when the user resizes one window of the layout ([S6]).
- **Preview highlighting**: the picker preview is a scratch buffer with filetype `snacks_picker_preview`.
  - `highlight()` resolves `ft` → `lang` with `vim.treesitter.language.get_lang`, then calls `vim.treesitter.start(buf, lang)`. If that fails, it sets `vim.bo.syntax = ft` ([S7], [S8]).
  - When the preview is reset, it calls `vim.treesitter.stop` and clears `syntax` ([S7]).
- **Mouse**: the list window maps `<2-LeftMouse>` to confirm. Scrolling with the wheel over a list is caught with `vim.on_key` + `getmousepos().winid` ([S11]).
- **Hooks**: replaces `vim.ui.select` (picker) and `vim.ui.input` (`snacks.input`) when they are enabled ([S9], [S10]).

### telescope.nvim — picker floats and preview

- Requires Neovim ≥ 0.11 ([T1]).
- **Preview**: tries `vim.treesitter.start(bufnr, lang)` after `language.get_lang`/`language.add`. If that fails, it sets the `syntax` option to `ft` ([T2]).
- **Mouse**: `<LeftMouse>` and `<2-LeftMouse>` are default mappings ([T3]).
- **Resize**: the picker re-runs its layout on `VimResized` ([T4]).
- Telescope is a picker. It has no form pattern beyond "prompt + list + preview".

### fzf-lua — preview only

- The builtin previewer starts treesitter with `pcall(vim.treesitter.start, bufnr, lang)` and falls back to regex syntax ([F1]). It can also replace `vim.ui.select` ([F2]).

### volt (nvzone) — interactive UI made of extmarks

- Used by NvChad's minty (colour picker with sliders), menu, typr and the base46 theme picker ([V3]).
- **Rendering**: fills the buffer with blank lines, then draws all content as `virt_text` extmarks at `virt_text_win_col` ([V2]).
- **Interaction**: a row/column table of "clickables" and "hoverables". `<Tab>`/`<S-Tab>` cycle the clickables, `<CR>` clicks. `vim.on_key` handles `<LeftMouse>` and `<MouseMove>` (hover) through `getmousepos()` ([V1]).
- **Global side effect**: `enable()` sets `vim.o.mousemev = true` for the whole editor ([V1]).
- **Text**: the content is not buffer text, so `/` search, `yank` and folds do not see it.
- **Docs**: the README says "Docs to be added soon before 2026" ([V3]).

## 3. Patterns, by concern

### 3.1 Layout

| Option | How | Resize | Focus/navigation | Notes |
|---|---|---|---|---|
| **A. Tabpage + splits** | `:tabnew`, then `nvim_open_win(buf, false, {split="left"/"right", win=…})` (0.10) or `:vsplit` | Neovim resizes the splits. Re-render only width-dependent text on `WinResized` | Native `<C-w>h/l`, mouse click focuses | Closest to a full-screen settings page. No z-index or backdrop problems. Users can resize panes with `<C-w><`/`>` |
| **B. Float layout** | 3 floats with `relative="editor"` (lazy, mason, telescope), or `snacks.layout` boxes | Our own `VimResized` (+ `WinResized`) handler recomputes sizes ([L2], [M3], [S6]) | Our own keys to cycle windows (snacks `cycle_win`, `<a-w>`) ([S12]) | Looks like a modal dialog. Needs `zindex`, an optional backdrop, and an explicit `border` (since 0.11, the global `'winborder'` is the default border) ([N2], [N11]) |
| C. One float with everything in one buffer | lazy.nvim style ([L3]) | One `VimResized` handler | Cursor only | The Preview cannot be a real buffer with its own treesitter highlighter in the same window. Rejected for the Preview |
| D. One window per widget | nui-components ([NC1]) | `nui.layout` | `<Tab>` between widget windows | Does not scroll. ~100 windows on large Tabs. Rejected |

- In both A and B, use **one buffer per pane**:
  - language list;
  - Option pane, with the Tab strip as its first lines or in its `'winbar'`;
  - Preview.
- Set `winfixbuf` on each pane (0.10, [N13]) so that `:e` and `:bnext` cannot replace the buffer. snacks' `fixbuf` does the same ([S3]).
- `'winbar'` on a float shows only if the window-local value is set ([N9b]). Since 0.12, floats can show a `'statusline'`, so set `style="minimal"` or an empty `statusline` to hide it ([N22]).

### 3.2 Rendering a pane (Option pane, language list)

The proven loop (lazy [L3]/[L4], mason [M3], neogit [G3]):

1. Build a view model from the state: a list of rows, each with segments `{text, hl}`, an optional `virt_text`, and the Option or item it belongs to.
2. `modifiable=true` → `nvim_buf_set_lines(buf, 0, -1, …)` → clear the namespace → `nvim_buf_set_extmark` per highlight → `modifiable=false`.
3. Restore the view: `winsaveview`/`winrestview` (lazy), or a "sticky cursor" by item id (mason). The cursor stays on the same Option when rows above it change, for example when a group collapses or a dependent Option appears.
4. Keep a row → Option index for the keymaps (lazy `locations`, mason per-line keybinds, neogit `RendererIndex`).
5. Coalesce bursts of changes: lazy throttles to 30 per second ([L5]), mason coalesces with `vim.schedule` ([M4]).

Extmark features that fit the Menu:

- `hl_group` + `end_col` for labels and values. `line_hl_group` for the selected row or for changed Preview lines (0.5+, [N4]).
- `virt_text_pos = "right_align"` (or `"eol_right_align"` in 0.11+, which does not cover long labels) for values aligned to the right edge. `"inline"` (0.10+) inserts a value or `[x]` without putting it in the buffer text ([N5], [N20]).
- Keep **labels as real buffer text**, so that `/` search finds an Option. Volt's approach (all content as virtual text) loses search ([V2]).
- Show disabled (dependent) Options with a dim highlight group. Navigation can skip them, and toggling them does nothing.

### 3.3 Input widgets

| Control kind | Display | Edit | Precedent |
|---|---|---|---|
| `checkbox` | `[x] Label` / `[ ] Label` | `<Space>`/`<CR>`/click toggles | nui-components `press_key = {"<CR>","<Space>"}` ([NC4]); volt checkbox ([V4]) |
| `radio`, `checkbox+radio` | `(•) Lower case  ( ) Upper case` under the parent checkbox | `<Space>` selects. The radios are disabled while the parent is unchecked (as in the corpus note) | — |
| `combo`, `wrap_combo` | `Label   [Do not wrap|Wrap if long|…]`, active choice highlighted, or only the active value | `h`/`l` (or `<`/`>`) cycles in place. `<CR>` → `vim.ui.select` | neogit `[a|b|c]` cycling ([G1], [G2]); mason `vim.ui.select` ([M5]) |
| `int_field` | `Label: 4` | `<CR>` → `vim.ui.input{default=…}`, then a min/max check (the corpus has `min`/`max`). Optional `<C-a>`/`<C-x>` to step the value | neogit config input ([G2]) |
| `text_field` (for example "Visual guides") | `Label: 80, 120` | `vim.ui.input` | — |
| `list_field` (PHPDoc tag order) | one item per line in a sub-buffer or float | Reorder with normal line editing or with mapped move keys. Commit on close | — |
| `group` | bold header with `▸`/`▾` | `<CR>`/`za` folds | neogit fold state ([G3]) |

- `vim.ui.select` and `vim.ui.input` exist since 0.6 ([R6]). Both are callback-based. Without a plugin, they use `inputlist()` and `input()` on the command line ([N16]). When snacks, fzf-lua or telescope-ui-select is installed, they show that plugin's UI, and we write no picker code ([S9], [S10], [F2]).
- A **prompt buffer** ([N24]) is the other way to edit text in place (nui `Input` [NU2]). Since 0.12 it supports multi-line input, undo and `prompt_getinput()` ([N23]). For single values, `vim.ui.input` is simpler and respects the user's UI choice.

### 3.4 Focus, navigation and keymaps

- All keymaps are **buffer-local** with `nowait=true` (lazy [L2], mason [M3]), so they never leak into user buffers.
- Within the Option pane, use `j`/`k` (native). Optionally, snap the cursor to Option rows or skip disabled rows, as lazy's next/prev jumps between `locations` ([L5]).
- For Tabs, follow the precedents: number keys (mason `1`–`5`, [M5]), a key shown in each pill (lazy, [L4]), or `[`/`]`-style keys. In splits, `<C-w>` moves between panes. In floats, use a cycle key (snacks `<a-w>` `cycle_win`, [S12]), or `<Tab>`/`<S-Tab>` (nui-components, volt; [NC2], [V1]).
- Show a key help line, for example in a float `footer` (0.10+, [N20]) or in the `winbar`.

### 3.5 Mouse

- `'mouse'` defaults to `"nvi"` since 0.8 ([N10b], [R8a]), so clicks reach buffer mappings by default.
- **Clicks on rows**: map `<LeftMouse>` buffer-locally, read `getmousepos()` (`winid`, `line`, `column`, [N14]), and toggle the Option on that row. This is what telescope and volt do ([T3], [V1]). `<2-LeftMouse>` can open a `vim.ui.select` (snacks maps it to confirm, [S11]).
- **Clickable Tab strip**: a `'winbar'` (0.8+, [R8b]) built from `%N@Func@label%X` click labels. Clicking calls `Func(minwid, clicks, button, mods)` ([N9]). Statusline and winbar click support landed in 0.8 ([R8b]).
- **The wheel** scrolls each window natively. snacks catches it with `vim.on_key` only because its list is virtual ([S11]). Since 0.11, an `on_key` callback can consume the key by returning `""` ([N15]).
- **Hover** needs the global `'mousemoveevent'`, which "can make pending mappings to be aborted when the mouse is moved" ([N10]). The Menu does not need hover, so avoid it.
- **Float `mouse` field** (0.11): set `mouse=false` on decorative floats (backdrop) so that clicks pass through ([N3], [N21]).

### 3.6 Re-rendering on resize

- **Splits**: Neovim resizes them. Re-render the Option pane on `WinResized` only if the text depends on width: right-aligned values, wrapping, truncation. `WinResized` (0.9+) gives `v:event.windows` ([N6], [R9b]).
- **Floats**: recompute the geometry on `VimResized` and call `nvim_win_set_config` (lazy, mason, telescope, snacks; [L2], [M3], [T4], [S4]). snacks also handles `WinResized` for user-resized windows of a layout, and moves the layout when its screen position changes ([S6]).

### 3.7 Preview buffer and syntax highlighting

- **Buffer**: `nvim_create_buf(false, true)` (scratch), `buftype=nofile`, `modifiable=false` between updates, `winfixbuf`.
- **Highlighting**: `vim.treesitter.start(buf, lang)` (0.8+, [R8c]; docs [N12b]). If it fails, set `vim.bo[buf].syntax = ft`. This is the shared pattern of snacks, telescope and fzf-lua ([S7], [T2], [F1]). The Language Plugin supplies the parser language name and the Vim syntax name.
  - Since 0.11, `vim.treesitter.language.add()` returns `true` when a parser is loaded, so snacks probes with it ([N17], [S8]).
  - The highlighter "parses code asynchronously, using a segment time of 3ms" ([N12b]), so replacing all lines does not block the UI.
- **Do not set the real `filetype`** on the Preview. snacks uses its own `snacks_picker_preview` filetype and still highlights by `lang` ([S7]). With the real filetype, `FileType` autocmds would attach LSP clients, linters, format-on-save, and ftplugin keymaps to a sample buffer.
- **Parsers**: Neovim bundles only the C, Diff, Lua, Markdown, Vimscript, Vimdoc and query parsers ([N12]). Neovim ships Vim syntax files for most corpus languages (`php.vim`, `javascript.vim`, `typescript.vim`, `css.vim`, `scss.vim`, `less.vim`, `sass.vim`, `html.vim`, `xml.vim`, `yaml.vim`, `json.vim`, `sh.vim`, `make.vim`, `markdown.vim`, `sql.vim`, `vue.vim`, `editorconfig.vim`, `mermaid.vim` in `runtime/syntax/` at [N0]). The fallback therefore gives every user highlighting.
- **Visible whitespace** as in PhpStorm's Preview: set window-local `list` + `listchars` (`space:·`, `tab:→ `) on the Preview window.
- **Updating on each change**: format the sample, then call `nvim_buf_set_lines` on the Preview inside `modifiable=true/false`, and keep the view with `nvim_win_call` + `winsaveview`/`winrestview` (lazy, [L4]). Optionally, mark changed lines with `line_hl_group` extmarks. Coalesce rapid toggles (mason [M4], lazy [L5]); the latency budget belongs to the "Preview performance" item of #1.

## 4. Minimum Neovim version per feature

| Feature | Since | Source |
|---|---|---|
| `nvim_open_win`, `nvim_win_set_config` (floats) | 0.4.0 | [N1] |
| Float `border` | 0.5 (PR #13998, merged 2021-03-22) | [R5] |
| `nvim_buf_set_extmark` (`hl_group`, `virt_text`, overlay/right_align), `nvim_win_call`, `nvim_set_hl` | 0.5.0 | [N1], [N4] |
| Virtual lines (`virt_lines`) | 0.6.0 | [R6] |
| `vim.ui.select`, `vim.ui.input` | 0.6.0 | [R6] |
| `vim.keymap.set` with Lua callbacks, `nvim_create_autocmd` | 0.7.0 | [R7] |
| `'winbar'`, click labels in statusline/winbar, `mouse=nvi` default, `vim.treesitter.start`, TUI `'mousemoveevent'` | 0.8.0 | [R8a], [R8b], [R8c] |
| Float `title`, `WinResized`, `nvim_get_hl` | 0.9.0 | [R9a], [R9b], [N1] |
| Inline virtual text, float `footer`, float `hide`, splits via `nvim_open_win`, `winfixbuf`, `nvim__redraw` | 0.10.0 | [N20], [N13], [N1] |
| Float `mouse` field, `virt_text_pos="eol_right_align"`, `'winborder'`, `vim.on_key` can consume keys, `language.add()` returns a boolean | 0.11.0 | [N21], [N15], [N17] |
| Floats can show `'statusline'`, prompt-buffer multi-line + `prompt_getinput()` | 0.12.0 | [N22], [N23] |

Minimum Neovim of the surveyed plugins: nui 0.5 ([NU1]), lazy 0.8 ([L1]), snacks 0.9.4 ([S1]), mason 0.10 ([M1]), neogit 0.10 ([G0]), telescope 0.11 ([T1]). Stable is 0.12.6, released 2026-10-09 ([R12]).

**Bottom line**: the recommended pattern needs **0.10**. 0.9 lacks inline virtual text, API splits and `winfixbuf`, and these have workarounds. **0.11** removes some workarounds (float `mouse`, `'winborder'` handling, `eol_right_align`).

## 5. Optional dependencies: what each costs and gives

| Dependency | Gives | Costs | Verdict |
|---|---|---|---|
| **None** (core API) | Full control, no install step. The precedents are lazy (UI in `lazy/view`, ~2.2k lines including plugin-specific render code) and mason (`mason-core/ui`, 826 lines) | We write a ~300–600-line renderer + layout + widget module | **Recommended** |
| **snacks.nvim** | `snacks.win`/`snacks.layout`: floats or splits from one config, nested boxes, backdrop, `fixbuf`, both resize events handled ([S3]–[S6]) | Needs Neovim ≥ 0.9.4. A large collection (~37k lines), but loaded per module ([S2]). Its own config and highlight conventions | Worth it **only if** we choose floats (layout B) |
| **nui.nvim** | `Popup`/`Split`/`Layout`/`Input`/`Tree`/`Line` primitives ([NU1]) | One more dependency for code we would write anyway. `Layout` has no resize handler of its own ([NU3]) | Low value |
| **nui-components.nvim** | Ready-made checkbox/select/text input/tabs/form/validation ([NC1]) | Needs nui. One float per widget, no form scrolling ([NC2]). Last push 2025-03 ([NC3]) | Does not fit Tabs with 100 Options |
| **volt** | Mouse hover and click, sliders, extmark-drawn layouts ([V1], [V4]) | Sets global `'mousemoveevent'` ([V1]). Content as virtual text only, so no search or yank ([V2]). No docs ([V3]) | Does not fit |
| **telescope / fzf-lua / snacks picker** | Nicer `vim.ui.select` | None for us: the user installs them, and `vim.ui.select` routes to them ([S9], [F2]) | Do not depend on them. Call `vim.ui.select` |
| **nvim-treesitter (parsers)** | Treesitter highlighting in the Preview for PHP, JS, … | Must be installed by the user. Neovim bundles only 6 parsers ([N12]) | Optional. Fall back to Vim syntax |

## 6. Open points for the prototype (#11)

- Layout A (tabpage + splits) or B (floats): compare them on resize, focus and how the Menu feels.
- How dropdowns are edited: inline cycle only, `vim.ui.select` only, or both.
- How to edit `list_field` and Arrangement rules (the Arrangement editor is listed under "Not yet specified" in #1).
- Where the Tab strip lives: the first buffer lines (searchable, works in splits) or `'winbar'` (fixed while scrolling, clickable).
- The floor: 0.10 or 0.11.

## Sources

Pinned commits used for the code citations:

- neovim `9290926c` (master, 2026-10-29)
- lazy.nvim `306a0552`
- mason.nvim `2a6940af`
- nui.nvim `10fc3618`
- nui-components.nvim `1654dd70`
- snacks.nvim `882c996c`
- telescope.nvim `40aedd8a`
- volt `4351c5cd`
- neogit `697ad3ee`
- fzf-lua `5b88d6f0`

Neovim docs and source:

- [N0] runtime/syntax: https://github.com/neovim/neovim/tree/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/syntax
- [N1] `api.txt`, "Since:" attributes of `nvim_open_win` (L3875, 0.4.0), `nvim_win_set_config` (L4066, 0.4.0), `nvim_get_hl` (L972, 0.9.0), `nvim__redraw` (L1872, 0.10.0): https://github.com/neovim/neovim/blob/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/doc/api.txt#L3875
- [N2] `nvim_open_win` `border` defaults to `'winborder'`: api.txt#L3934
- [N3] `nvim_open_win` `focusable`, `mouse`, `hide`, `relative`, `split`, `style`, `title`, `zindex`: api.txt#L3971-L4028
- [N4] `nvim_buf_set_extmark` (Since 0.5.0) and `line_hl_group`: api.txt#L3236, #L3311
- [N5] `virt_text_pos` values `eol`, `eol_right_align`, `overlay`, `right_align`, `inline`; `virt_text_win_col`: api.txt#L3367-L3385
- [N6] `WinResized` autocmd, `v:event`: https://github.com/neovim/neovim/blob/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/doc/autocmd.txt#L1571
- [N9] `'statusline'` `@` click label: https://github.com/neovim/neovim/blob/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/doc/options.txt#L6566
- [N9b] `'winbar'` on floats needs a window-local value: options.txt#L7685
- [N10] `'mousemoveevent'`, global, may abort pending mappings: options.txt#L4701
- [N10b] `'mouse'` default `"nvi"`: options.txt#L4588
- [N11] `'winborder'`: options.txt#L7711
- [N12] Bundled parsers: https://github.com/neovim/neovim/blob/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/doc/treesitter.txt#L24
- [N12b] `vim.treesitter.start()`, async parsing with a 3 ms segment: treesitter.txt#L1197
- [N13] `'winfixbuf'`: options.txt#L7744; added in 0.10: news-0.10.txt#L312
- [N14] `getmousepos()`: https://github.com/neovim/neovim/blob/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/doc/vimfn.txt#L4121
- [N15] `vim.on_key()` discards the key when the callback returns `""`: lua.txt#L1745; news-0.11.txt#L249
- [N16] Default `vim.ui.select` uses `inputlist()`, `vim.ui.input` uses `input()`: https://github.com/neovim/neovim/blob/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/lua/vim/ui.lua#L63-L139
- [N17] `language.add()` returns `true` when a parser is loaded (0.11): news-0.11.txt#L137
- [N20] 0.10 news: inline virtual text (L149), float `hide` (L154), `footer` (L160), splits via `nvim_open_win` (L166): https://github.com/neovim/neovim/blob/9290926ccf55ba3f55e4b48f5b94cad403017688/runtime/doc/news-0.10.txt#L149
- [N21] 0.11 news: float `mouse` field (L168), `eol_right_align` (L174), `'winborder'` (L314): news-0.11.txt#L168
- [N22] 0.12 news: floats can show `'statusline'`: news-0.12.txt#L112
- [N23] 0.12 news: prompt-buffer multi-line/undo (L176), `prompt_getinput()` (L429): news-0.12.txt#L176
- [N24] Prompt buffer: channel.txt#L175

Neovim release notes:

- [R5] Float borders, PR #13998 "floats: add MS-DOS mode (borders)", merged 2021-03-22, before v0.5.0 (2021-07): https://github.com/neovim/neovim/pull/13998
- [R6] v0.6.0: "decorations: support virtual lines", "ui: add vim.ui.select", "ui: add vim.ui.input": https://github.com/neovim/neovim/releases/tag/v0.6.0
- [R7] v0.7.0: "lua: add vim.keymap", "api: add api and lua autocmds": https://github.com/neovim/neovim/releases/tag/v0.7.0
- [R8a] v0.8.0: "defaults: enable mouse by default (set mouse=nvi) #19290": https://github.com/neovim/neovim/releases/tag/v0.8.0
- [R8b] v0.8.0: "ui: Add 'winbar'", "Click support for 'statusline', 'winbar' #18650", "tui: Support 'mousemoveevent'": same page
- [R8c] v0.8.0: "treesitter: Add vim.treesitter.start()": same page
- [R9a] v0.9.0: "ui: Add support to display a title in the border of a float (#20184)": https://github.com/neovim/neovim/releases/tag/v0.9.0
- [R9b] `WinResized`, PR #21161 (vim-patch 9.0.0917), merged 2022-11-23, between v0.8.0 (2022-09) and v0.9.0 (2023-04): https://github.com/neovim/neovim/pull/21161
- [R12] Latest stable v0.12.6 (2026-10-09): https://github.com/neovim/neovim/releases/tag/v0.12.6

lazy.nvim (`https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/…`):

- [L1] README.md#L61 (Neovim ≥ 0.8.0); lua/lazy/init.lua#L52
- [L2] lua/lazy/view/float.lua: backdrop float #L145, `VimResized` relayout #L190-L215, buffer-local `nowait` keys #L252-L261
- [L3] lua/lazy/view/text.lua#L62-L112 (set_lines + one extmark per segment)
- [L4] lua/lazy/view/render.lua: `update()` with modifiable toggle and winsaveview #L33-L100, `get_plugin(row)` via `locations` #L103-L124, "pills" mode buttons #L136-L165
- [L5] lua/lazy/view/init.lua: throttled update #L71, re-render on `LazyRender`/`LazyFloatResized` #L75-L82, next/prev item #L115-L135; throttle default `1000 / 30`: lua/lazy/core/config.lua#L125

mason.nvim (`https://github.com/mason-org/mason.nvim/blob/2a6940af80375532e5e9e7c1f2fc6319a1b7a69d/…`):

- [M1] README.md#L83 (neovim ≥ 0.10.0)
- [M2] lua/mason-core/ui/init.lua (node types, `Keybind`, `StickyCursor`, `Table`)
- [M3] lua/mason-core/ui/display.lua: per-line effect dispatch #L259-L280, `draw()` #L283-L378, `VimResized` #L464-L476, state subscription #L528-L540
- [M4] lua/mason-core/ui/display.lua#L11-L26 (`debounced` via `vim.schedule`); lua/mason-core/ui/state.lua
- [M5] lua/mason/ui/instance.lua: global keybinds `1`–`5` switch views #L32-L36, `vim.ui.select` for the language filter #L506

neogit (`https://github.com/NeogitOrg/neogit/blob/697ad3ee86a73cf6b6758b838d7a7d76cf3b9f86/…`):

- [G0] README.md#L15 (Neovim 0.10+)
- [G1] lua/neogit/lib/popup/ui.lua#L21-L60 (`[a|b|c]` config choices with the active one highlighted)
- [G2] lua/neogit/lib/popup/init.lua: `set_option` (choices → fuzzy finder, else input) #L183-L200, `set_config` cycles choices in place #L256-L275
- [G3] lua/neogit/lib/ui/init.lua#L684-L720 (re-render, restore cursor/top line, fold state); lua/neogit/lib/ui/renderer.lua (`RendererIndex`)
- [G4] lua/neogit/lib/input.lua#L2 (`vim.ui.input` wrapped async)

nui.nvim / nui-components.nvim:

- [NU1] https://github.com/MunifTanjim/nui.nvim/blob/10fc361835c856ba4233ef5ea135b919bf3dce97/README.md#L12 (Neovim 0.5.0, component list)
- [NU2] …/lua/nui/input/init.lua#L50-L103 (`buftype=prompt`, `on_change`, `on_submit`)
- [NU3] …/lua/nui/layout/init.lua#L412 (`Layout:update`); no `VimResized` handler in `lua/nui` except the event name table in `lua/nui/utils/autocmd.lua#L228`
- [NC1] https://github.com/grapp-dev/nui-components.nvim/blob/1654dd709f13874089eefc80d82e0eb667f7fdfb/lua/nui-components/component/init.lua#L10 (`Component = Popup:extend`); component files in `lua/nui-components/`
- [NC2] …/lua/nui-components/renderer.lua#L31-L32 (`focus_next = "<Tab>"`), #L140-L151 (`nui.layout` of components); scrolling only in `tree.lua`/`buffer.lua`
- [NC3] GitHub API `pushedAt: 2025-03-15T18:28:06Z`, not archived: https://github.com/grapp-dev/nui-components.nvim
- [NC4] …/lua/nui-components/checkbox.lua#L15 (`press_key = { "<CR>", "<Space>" }`)

snacks.nvim (`https://github.com/folke/snacks.nvim/blob/882c996cf28183f4d63640de0b4c02ec886d01f2/…`):

- [S1] README.md#L48 (Neovim ≥ 0.9.4)
- [S2] lua/snacks/init.lua#L5-L7 (lazy `require` per module)
- [S3] lua/snacks/win.lua#L66-L87 (`minimal`, `position`, `backdrop`, `fixbuf`, `resize`)
- [S4] lua/snacks/win.lua#L315-L337 (`WinResized`, `VimResized` → `on_resize`)
- [S5] lua/snacks/layout.lua#L17-L70 (box tree; split layouts wrapped in a box)
- [S6] lua/snacks/layout.lua#L125-L164 (`WinResized` and `VimResized` relayout)
- [S7] lua/snacks/picker/core/preview.lua#L256-L263, #L280, #L290-L310 (`treesitter.stop`, custom filetype, `treesitter.start` with `syntax` fallback)
- [S8] lua/snacks/util/init.lua#L40-L48 (`get_lang` via `language.get_lang`/`language.add`)
- [S9] lua/snacks/picker/init.lua#L94 (`vim.ui.select = M.select`)
- [S10] lua/snacks/input.lua#L304 (`vim.ui.input = M.input`)
- [S11] lua/snacks/picker/core/list.lua#L43-L60 (wheel via `vim.on_key` + `getmousepos`); lua/snacks/picker/config/defaults.lua#L286 (`<2-LeftMouse>`)
- [S12] lua/snacks/picker/config/defaults.lua#L245 (`<a-w>` → `cycle_win`)

telescope.nvim (`https://github.com/nvim-telescope/telescope.nvim/blob/40aedd8a68c78a656a10a8d62d80c54af59420fb/…`):

- [T1] plugin/telescope.lua#L1 (`has "nvim-0.11"` check)
- [T2] lua/telescope/previewers/utils.lua#L154-L175 (`ts_highlighter` → `vim.treesitter.start`, `regex_highlighter` → `syntax`)
- [T3] lua/telescope/mappings.lua#L133-L141 (`<LeftMouse>`, `<2-LeftMouse>`)
- [T4] lua/telescope/pickers.lua#L710 (`VimResized`)

fzf-lua (`https://github.com/ibhagwan/fzf-lua/blob/5b88d6f0af7fcb41d4a8bb340bf70d7e3824ee9d/…`):

- [F1] lua/fzf-lua/previewer/builtin.lua#L1039-L1047 (`ts_attach` → `vim.treesitter.start`)
- [F2] lua/fzf-lua/providers/ui_select.lua#L45 (`vim.ui.select = M.ui_select`)

volt (`https://github.com/nvzone/volt/blob/4351c5cd790a0d39491c4d5c75dd62d7db3d3414/…`):

- [V1] lua/volt/events.lua: `<CR>`/`<Tab>`/`<S-Tab>` #L84-L97, `enable()` sets `vim.o.mousemev = true` and handles `<LeftMouse>`/`<MouseMove>` via `vim.on_key` + `getmousepos` #L116-L135
- [V2] lua/volt/init.lua#L63-L70 (buffer filled with blank lines); lua/volt/draw.lua#L48 (`virt_text_win_col` extmarks)
- [V3] README.md (showcase; "Docs to be added soon before 2026", L37)
- [V4] lua/volt/ui/components.lua (`checkbox`, `progressbar`, …)

Research Corpus (read-only): `~/Projects/phpstorm-editorconfig/data/ui-structure.json` (control kinds and counts computed from `pages.*.tabs`), `screenshots/php/02-spaces-1.png`, `screenshots/php/03-wrapping-and-braces-1.png`.
