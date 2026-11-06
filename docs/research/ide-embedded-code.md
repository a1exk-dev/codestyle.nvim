# What the PhpStorm IDE does to embedded code that the records cannot show

Task for issue [#26](https://github.com/a1exk-dev/codestyle.nvim/issues/26) (map: [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)). It follows "How is embedded code that is not a template formatted?" ([#24](https://github.com/a1exk-dev/codestyle.nvim/issues/24)), whose findings came from the command-line formatter only.

Date: 2026-11-06. PhpStorm 2026.2.3, project `~/phpstorm-editorconfig` of the Research Corpus, driven with the corpus's `tools/gui/ui`. Terms follow `GLOSSARY.md`.

## Answer

- **Reformat Code in the IDE formats exactly what the command-line formatter formats, except Vue `{{ }}`.** On all 5 inputs and 6 controls, under all 4 schemes (44 pairs), the IDE output is byte-identical to the CLI output, except the one Vue interpolation (`{{item.name}}` → `{{ item.name }}`), which the corpus already records (`docs/notes/BEHAVIOR-GUI-1.md` §1). So the "not formatted" results of #24 hold in the IDE too.
- **Not formatted, in the IDE as in the CLI** (each part is shown as injected code in the editor, see `screenshots/`, so this is the formatter's choice, not a missing injection):
  - Blade `{{ }}`, `{!! !!}`, directive arguments (`@if(   $a==1&&$b   )`, `@foreach($items   as   $i=>$item)`) and `@php … @endphp` bodies. The `@php` body lines only get the Blade block indent; the Blade indent (2 instead of 4) moves them, the PHP indent (8) does not.
  - Vue directive values (`v-if`, `:prop`, `:obj`, `@click`, `v-for`, `:key`), also a multi-line `:class` value, whose lines stay at column 0.
  - HTML `style=` and `onclick=` values, one-line and multi-line. The multi-line value lines are not re-indented under any scheme.
  - PHP `<<<HTML`, `<<<SQL` and `<<<JS` heredoc bodies, and strings marked with `// language=JavaScript|CSS|HTML`. No scheme changed them.
- **`<script>` and `<style>` in a `.php` file with inline HTML use the JS and CSS indent, measured from the tag, which follows the HTML indent.** This is the same rule as in HTML, Twig and Blade (ADR-0008), and it qualifies ADR-0005's "A PHP file with inline HTML uses HTML's indent Options for all of its lines":
  - Default (HTML, JS, CSS all 4): `<style>` at 4, `body {` at 8, `margin: 0` at 12.
  - JS 8, CSS 2: `<style>` at 4, `body {` at 6, `margin` at 8; `<script>` at 4, `function` at 12, `if` at 20, `return` at 28.
  - HTML 2: `<style>` at 2, `body {` at 6 (2 + CSS 4); `<script>` at 2, `function` at 6.
  - PHP 8: no change (the PHP code in this file is one-line `<?php … ?>` and `<?= ?>` pieces).
- **Side observation, Blade `<?php ?>`:** with PHP indent 8, the `<?php` line moves to 8 (one PHP indent inside `<div>`) and the body nests by 8 from it (`if` at 8, `$w = 3;` at 16). The CLI gives the same output, and `blade/php.indent_size.json` already records the rule.

## Method

- Inputs (`inputs/`): `blade.blade.php`, `vue.vue`, `attrs.html`, `heredoc.php`, `inline.php`. Each is written unformatted (no indent, no spaces around operators), so any formatting shows.
- Schemes (`schemes.py`): `default`; `js8_css2` (JavaScript indent 8, CSS 2); `html2_vue4_blade2` (HTML 2, Vue 4, Blade 2); `php8` (PHP 8). Each changes only `INDENT_SIZE` of the named languages, with different values so that one run tells them apart.
- IDE (`ide.py`): writes the scheme as `.idea/codeStyles/Project.xml`, then reformats a probe control until it shows the scheme (the IDE re-reads the file late; a first run without the probe gave stale results and was discarded). Then, for each file: a fresh copy, opened in the running IDE, caret at the file start, Ctrl+Alt+L, Ctrl+S. The controls (`controls/`, one per language) run after the inputs, and each shows its scheme, so the scheme stayed loaded. The project's code style files were restored afterwards. Outputs: `ide/<scheme>/`.
- CLI (`cli.py`): the corpus's `tools/behavior/fmt.py` (isolated `phpstorm format` workers) with the same schemes. Outputs: `cli/<scheme>/`.
- `results.json`: per scheme and file, whether the IDE changed the input, differs from the Default output, and equals the CLI output.
- One run each. The Default scheme was run twice with identical outputs.

## Not covered

- Relative indents inside unformatted bodies (`@php`, heredocs): every input body started at column 0, so whether the IDE keeps a body's inner nesting is not shown.
- Embedded languages' other Options (spaces, wrapping) inside `<script>`/`<style>` in a `.php` file: only Default values; the bodies are formatted by the JS and CSS formatters, as in HTML.
- `<<<SQL` with a configured SQL dialect or data source; the project has none.
- Selection reformat.
