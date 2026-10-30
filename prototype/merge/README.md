# PROTOTYPE: merge of host and embedded-language block trees (throwaway)

Answers "How does the Core merge host and embedded-language block trees?" ([#19](https://github.com/a1exk-dev/codestyle.nvim/issues/19), map [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)).
This branch is never merged.

The prototype parses PHP and Twig files with Neovim's Tree-sitter, so it is headless Lua, not an HTML page.
Three toy Language Plugins (PHP, HTML, Twig) build block trees. The Core merges them and then runs an indent-only pass.
The pass rewrites the indent of each line and leaves the rest of each line alone.

## Run

From the repository root:

```sh
nvim --headless -l prototype/merge/run.lua                     # golden check against the Behaviour Records
nvim --headless -l prototype/merge/run.lua show <file> [php.indent_code_in_php_tags=true …]
```

`show` prints the merged block tree, the host blocks that were split because they cross HTML, the owner of each line's indent, the owner of each gap, the time, and the result.
The PHP, Twig and HTML parsers come from your setup (nvim-treesitter). Otherwise set `CODESTYLE_PARSERS` to a directory with `php.so`, `twig.so` and `html.so`.
The Research Corpus is read from `~/Projects/phpstorm-editorconfig`, or from `CODESTYLE_CORPUS`.

Files to try:

- `~/Projects/phpstorm-editorconfig/tests/formatter/php/tabs_and_indents/{html_template,r2_html_template,r2_php_first_then_html}.php`
- `~/Projects/phpstorm-editorconfig/tests/formatter/twig/tabs_and_indents/{indent,nesting}.twig`
- the Previews `~/Projects/phpstorm-editorconfig/data/code-samples/{PHP,Twig}/*.txt` (the PHP Previews contain no HTML)
- `prototype/merge/samples/crossing.php`: a PHP block that crosses two `<div>`s
- `prototype/merge/samples/unbalanced.php`: `if`/`else` branches that each open a `<div>`

## Result

**65 of 68 golden cases match PhpStorm**, and the other 3 are known mismatches that are not about the merge.
The input of each case is PhpStorm's output with every indent removed. The cases cover the PHP files with inline HTML (Default, "Indent code in PHP tags", PHP and HTML indent 2, PHP and HTML tabs) and the Twig `tabs_and_indents` files (Default, indent 2 and 8, tabs).
The 3 known mismatches are in `attributes.twig` with tabs. PhpStorm wrapped those attribute lines itself. A line break that the formatter adds aligns with tabs plus spaces, and a line break from the input is all tabs. That is a question for the engine, not for the merge.

## The model

1. **Each Language Plugin builds its own block tree from its own parse tree.** A block is not always a node:
   - **Holes**: PHP `text` and Twig `content` make no block. The HTML tree fills them.
   - **Splice**: PHP `text_interpolation` (`?> … <?php`) and `colon_block` are glue that crosses HTML elements, so their children go to the parent.
   - **Synthetic blocks**: PHP groups `<?php … ?>` into a region, which "Indent code in PHP tags" indents. The Twig grammar is flat: `{% if %}` and `{% endif %}` are sibling nodes. So the Twig plugin pairs the tags into blocks, and those blocks give the HTML between the tags its indent.
   - **Leaf ranges are trimmed**: Twig directive nodes start with the newline before them.
   - **Read-only blocks** keep their text: comments, `{% verbatim %}`, `ERROR` nodes, and an HTML element that is not closed.
2. **The Core merges the trees. Markup is primary** (IntelliJ's `TemplateFormatUtil.mergeBlocks`):
   - At each markup level, the host leaves that sit directly between the markup children span a range R. The topmost host blocks that fit in R join that level.
   - A block that contains blocks of the other tree takes them in as children.
   - A host block that crosses a markup block is split into its children. Markup blocks are never split.
   - A markup leaf that contains host code (a Twig `{% if %}` inside an attribute value) keeps it as text.
   - The HTML document spans the whole file. The host root takes part only when its leaves span the whole level. That reproduces PhpStorm's 4-column indent of the top-level `<div>` in `r2_php_first_then_html.php`.
3. **Indent**: a block's indent kind (none, normal, continuation, or align to a block) comes from **its parent's** Language Plugin, also when the child is of the other language. The base is the new indent of the line where the parent starts. An indent applies only to a block that starts a line.
4. **Indent sizes**: one set of indent Options applies to the whole file, and the **host** Language Plugin picks it. PHP files with inline HTML use HTML's indent, continuation indent and tabs (PHP's are ignored). Twig files use Twig's (HTML's are ignored). Both rules come from the Behaviour Records.
5. **Gap ownership**: the lowest block that holds both leaves owns the gap and decides its Spacing. A gap between two HTML words inside `{% block %}` belongs to the Twig block. So a plugin's spacing rules must handle children of another language.

## Stubs and limits

- Only indentation. There is no Spacing, Wrap or blank-line handling. The gap owners are reported but not used.
- The PHP, HTML and Twig rules are just enough for the test files.
- `<script>` and `<style>` are read-only leaves. Vue and Blade are not covered, because their host tree contains the HTML structure.
- An unclosed `<div>` (`samples/unbalanced.php`) keeps its text. tree-sitter-html reports no error there, so the HTML plugin detects it.
