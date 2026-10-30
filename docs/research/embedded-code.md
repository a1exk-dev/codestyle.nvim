# Formatting of embedded code that is not a template

Research for issue [#24](https://github.com/a1exk-dev/codestyle.nvim/issues/24) (map: [#1](https://github.com/a1exk-dev/codestyle.nvim/issues/1)). It feeds "What is the Language Plugin contract?" ([#12](https://github.com/a1exk-dev/codestyle.nvim/issues/12)).
Question: how does PhpStorm format embedded code that is not a template, and what does it need from the Core and the Language Plugins? The cases are `<script>` and `<style>` in HTML, Vue `<script>`/`<style>`/`{{ }}` and directive values, Blade, and PHP heredoc/nowdoc injections.

Date of research: 2026-10-31. Sources: the Research Corpus (PhpStorm 2026.2.3), IntelliJ Community and intellij-plugins at tag `idea/262.10968.63` (Apache-2.0), Neovim 0.12.6, nvim-treesitter `main` at `a2f6944` (also `master` at `cf12346`), tree-sitter-blade at `b5291d1`. Terms follow `GLOSSARY.md`. This note presents findings and options. It does not decide.

## Answer

- **IntelliJ has one mechanism for all non-template embedding: the embedded Block.** When the host's Block builder meets a part in another language, it asks that language's own formatter for a Block tree and hangs the tree under one host Block (`AnotherLanguageBlockWrapper`) [I1][I4][I5]. The host gives the wrapper its indent (normal or none). The Gaps inside the part belong to the Embedded Language. The Gaps at the borders (after `<script>`, around `{{ }}`) belong to the host. The two trees do not interleave, so nothing is merged. This differs from the template merge of ADR-0005.
- **Indent Options are chosen per Block, by the Block's language.** IntelliJ computes each line's indent with the indent Options of the language of the line's first leaf Block. A Block with no language uses the file's indent Options, which the Host Language chooses. A file can set an "override" flag, and then every Block uses the file's indent Options [I10][I11]. The results:
  - **HTML:** `<script>` and `<style>` bodies use the JavaScript and CSS indent. The HTML Option "Use HTML indents within `<style>` and `<script>` tags" (off by default) switches them to the HTML indent [I9] (`html/indent_size.json`, `html/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json`).
  - **Vue:** "Same in the whole file" is on by default, so the Vue indent (2) applies to the template, `<script>` and `<style>`. With "Specific to the language in the block", the parts use the HTML, JS/TS and CSS/SCSS indents [V1] (`vue-template/VueCodeStyleSettings.UNIFORM_INDENT.json`).
  - **Twig and Blade:** they are templates (the Twig or Blade indent applies to the HTML), but `<script>` and `<style>` bodies still use the CSS/JS indent. The HTML "uniform indent" Option has no effect there (`blade/` and `twig/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json`).
- **The body sits at the column of its tag plus one indent of the Embedded Language.** Example: HTML indent 2, JS indent 4 puts `<script>` at 2 and `function` at 6 (`html/indent_size.json`). Host Options can stop this indent. HTML "Keep white spaces" keeps the body's first line where the source has it (`html/ij_html_keep_whitespaces.json`). Vue "Indent children of top-level tag" sets it to none for unlisted tags (`vue-template/ij_vue_indent_children_of_top_level.json`; default `template`, so Vue `<script>` and `<style>` bodies start at column 0). The leading whitespace of each embedded line is written with the Embedded Language's tab Options. With HTML on tabs and JS on spaces, the `<script>` line gets a tab and its body gets spaces only (`html/indent_style.json`).
- **All other Options inside the part (spaces, blank lines, braces, wrapping) come from the Embedded Language's own Code Style.** The Default outputs show the CSS formatter in `<style>` and the TypeScript formatter in Vue `<script setup lang="ts">`. No Behaviour Record varies a JS or CSS Option on an HTML or Vue input, so this is shown only for default values.
- **What PhpStorm formats:**
  - **Formatted:** `<script>` and `<style>` in HTML, Vue, Twig and Blade. `<?php … ?>` blocks in Blade, with the PHP Code Style; they sit one PHP indent inside their HTML parent (`blade/php.indent_size.json`). Vue `{{ }}` interpolations, in the IDE only (`tests/gui/vue/`).
  - **Not formatted:** HTML attribute values (`style="…"`, `onclick="…"`) and, by the open source, Vue directive values (`:title="a+b"`). IntelliJ makes attribute values read-only Blocks [I3]. Blade `{{ }}`, `{!! !!}`, directive arguments and `@php … @endphp` bodies, which only get the Blade block indent (`blade/php.*.json`). PHP heredoc and nowdoc bodies, including a `<<<SQL` body, in 56 outputs of 5 records. "Place on the same line as variable declaration" only moves a body and its closing marker as one unit (`php/ij_php_heredoc_on_same_line.json`).
- **Caveat: the Behaviour Records come from the command-line formatter, and it never formats injected fragments.** In the IDE, Vue `{{a+b}}` becomes `{{ a + b }}`. With the command-line formatter it stays as written (`docs/notes/BEHAVIOR-GUI-1.md` §1). So every "not formatted" result for an injection (Blade PHP pieces, heredocs, attribute values) is a command-line fact. The IDE was not checked for them.
- **Neovim gives one child LanguageTree per Embedded Language. Each non-combined injection is its own `TSTree` with buffer-absolute positions** [N1][E1]. `<script>`, `<style>`, Vue `{{ }}` and directive values, Blade `php_only` pieces and heredoc bodies are all such separate trees. Each tree sits inside one host leaf (`raw_text`, `php_only`, `parameter`, `heredoc_body`), so building Blocks needs a graft, not a merge. Blade on nvim-treesitter `main` is one tree whose HTML and Blade nodes nest together. On the old `master` branch it is a flat tree with a combined HTML injection, like Twig [N2][N3].
- **The user's injection queries do not pick the language that PhpStorm picks.** Five gaps were seen:
  - `<script type="text/babel">` (JSX), `<script type="text/template">` (PhpStorm formats it as HTML) and `<script lang="ts">` in HTML get no injection.
  - `style=` and `on*=` attribute values do get an injection, although PhpStorm leaves them alone.
  - Vue expressions are injected as `typescript`.
  - Vue `<style lang="less|sass|postcss">` is parsed as `scss`.
  - `<<<JS` resolves to no parser.

  So the host Language Plugin, not the user's queries, should decide where code is embedded and which language it is in.
- **Non-template embedding follows different rules from ADR-0005.** In a template, one set of indent Options covers the template layers, because the Host Language chooses them for the whole file and template Blocks carry no language. Embedded Blocks carry their own language, so they keep their own indent Options. One rule covers both: a Block uses its language's indent Options, else the file's, unless the file overrides. Twig and Blade `<script>` bodies follow the CSS/JS indent. So ADR-0005's sentence "One set of indent Options … applies to the whole file" needs a qualifier for `<script>` and `<style>` in templates.
- **What this asks of the Core (options below):** an embedded-Block graft. Each Block carries a language, and indent Options are resolved per Block with a host override flag. Lines are rendered with the indent Options of the line's leaf. Border Gaps belong to the host. **What it asks of the Language Plugins:** the host declares each embed point (range, Embedded Language, indent kind) and may override indent Options. The Embedded Language's plugin builds Blocks for a range that is not a whole file. When that plugin or its parser is missing, the part becomes a read-only leaf.

## 1. How IntelliJ formats an embedded part

Sources: the open XML/HTML formatter in `intellij-community` [I1]–[I9] and the open Vue formatter in `intellij-plugins` [V1][V2]. Blade, Twig, PHP, JavaScript and CSS formatters are closed. For those we have the Behaviour Records only.

**Two ways in, one wrapper.**

1. **A child in another language.** In an HTML file, the body of `<script>` is a child PSI node in the JavaScript language, not an injection. `AbstractXmlBlock.processChild` checks `useMyFormatter(myLanguage, childLanguage, childPsi)`. This returns true when the child is HTML/XML, or when the child's language has no formatter. Otherwise it calls `myInjectedBlockBuilder.addInjectedLanguageBlockWrapper(result, child, indent, 0, null)` ([I1] L197–238, L378–389).
2. **A real language injection** (Vue `{{ }}`, IE conditional comments). `XmlTagBlock.processChild` calls `buildInjectedPsiBlocks` for `XML_TEXT` and comments ([I2] L163–191). This enumerates the injections of the host node and adds blocks for the text before and after each one ([I5] L52–134). Its Javadoc uses `{{1+ 2 }}` as the example and explains how the HTML text Blocks and the injected Blocks are combined ([I2] L193–215).

Both paths end in `InjectedLanguageBlockBuilder.addInjectedLanguageBlockWrapper` ([I5] L156–180). It looks up the child language's `FormattingModelBuilder` and creates a whole model with the **host's** `CodeStyleSettings` object, which holds every language's Options (`FormattingContext.create(childPsi, getSettings())`, L166). Then it wraps the model's root Block. For XML/HTML the wrapper is `AnotherLanguageBlockWrapper` ([I6] L25–33):

- `getIndent()` returns the indent that the host passed in ([I4] L30–33).
- Its children are the embedded root's children, and `getSpacing()` asks the embedded root ([I4] L50–63). So every Gap inside the part follows the Embedded Language's rules.
- The Gaps between the wrapper and its host siblings are decided by the host parent. One example is `VueSyntheticBlock.getSpacing`, which spaces `{{` and `}}` around the expression with Vue Options ([V1] `VueSyntheticBlock.kt` L28–58).

A **missing formatter** is handled by `useMyFormatter`: when `LanguageFormatting.forLanguage(childLanguage)` is null, the host formats the child as its own simple Block ([I1] L385–388). A multi-line text child becomes one leaf with a trimmed range ([I1] L307–330), so the lines inside it keep their text. The corpus shows this with a Vue `<i18n>` custom block, whose content "is never re-indented" (`vue-template/ij_vue_indent_children_of_top_level.json` notes).

**Attribute values are read-only.** `XmlBlock.buildChildren` sends `XML_ATTRIBUTE_VALUE` to `splitAttribute`. That method makes a `ReadOnlyBlock` for the value unless the value contains template code ([I3] L79–81, L137–157). Vue does not override this ([V1] `VueBlock.kt`, `VueHtmlBlock.kt`). So `style="…"`, `onclick="…"`, `:title="…"` and `@click="…"` are not formatted by a host Reformat. This is inferred from the source. No record or IDE run varies them.

**Formatting is driven from the top-level file.** `CodeFormatterFacade.processRange` builds the model of the file that contains the element. If the element is inside an injected fragment, it formats the top-level file by default (`shouldDelegateToTopLevel`) ([I12] L80–131, L387–398). So an injected fragment is formatted during Reformat Code only if the host's model builds a Block for it. This is why the formatting of injections is the host's job.

## 2. Which indent Options apply

The engine resolves indent Options per Block:

```java
// BlockIndentOptions.getIndentOptions(AbstractBlockWrapper block)   [I10]
if (myIndentOptions.isOverrideLanguageOptions()) return myIndentOptions;   // file-wide override
final Language language = block.getLanguage();                              // only BlockEx blocks have one
if (language != null) { ... return mySettings.getCommonSettings(language).getIndentOptions(); }
return myIndentOptions;                                                     // the file's indent Options
```

- `AbstractBlockWrapper` takes the language only from blocks that implement `BlockEx` ([I10] `AbstractBlockWrapper.java` L56–65). Ordinary `AbstractBlock`s have no language.
- `IndentAdjuster` computes a line's indent with the Options of the line's **leaf** Block ([I10] `IndentAdjuster.java` L53–57). That is why a `<script>` body line is written entirely in JS's tab setting.
- `setOverrideLanguageOptions(true)` makes "the indent options override options defined for a language block" ([I11] L1168–1185). File indent providers set it:
  - `HtmlFileIndentOptionsProvider`: when `HTML_UNIFORM_INDENT` is on, and only for file types whose language "is kind of" HTML ([I9] L18–31). Blade and Twig are not, which matches their no-effect records.
  - `VueFileIndentOptionsProvider`: Vue indent with override when `UNIFORM_INDENT` is on (default `true`), else the HTML indent Options without override. It also copies HTML's common settings onto Vue's ([V1] L16–45).
- The right margin is the one of the file's base language (`calcRightMargin`, [I10] L51–66). This is from the source only. No record tests the right margin inside an embedded part.

| File | Template layers (HTML, host tags) | `<script>` / `<style>` / embedded PHP body | Evidence |
|---|---|---|---|
| `.html` | HTML indent | JS / CSS indent; HTML indent if "Use HTML indents within `<style>` and `<script>`" | `html/indent_size.json`, `html/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json` |
| `.vue`, "Same in the whole file" (default) | Vue indent | Vue indent | `vue-template/indent_size.json` |
| `.vue`, "Specific to the language in the block" | HTML indent | JS/TS, CSS/SCSS indent | `vue-template/VueCodeStyleSettings.UNIFORM_INDENT.json` |
| `.twig` | Twig indent (ADR-0005) | JS / CSS indent; the HTML Option has no effect | `twig/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json` |
| `.blade.php` | Blade indent | JS / CSS indent; `<?php ?>` PHP indent | `blade/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json`, `blade/php.indent_size.json` |
| `.php` with inline HTML | HTML indent (ADR-0005) | **not recorded** | no `.php` input has `<script>` or `<style>` |

## 3. Case 1: `<script>` and `<style>` in HTML

Twenty HTML records have inputs with `<script>` or `<style>` (`indent.html`, `script_style.html`, `misc.html`).

**The body follows the Embedded Language's indent, measured from the tag.** `html/indent_size.json`, value `2`, `indent.html` (CSS and JS indent stay at 4). The record's note: "The indent of `<style>` and `<script>` content is not Indent of HTML but the indent size of CSS / JavaScript":

```html
  <style>
      body {
          margin: 0;
      }
  </style>
  <script>
      function f() {
          return 1;
      }
  </script>
```

With value `8`, `<style>` is at 8 and `body {` at 12, so the body is still 4 from the tag.

**The HTML Option moves the body to the HTML indent.** `html/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json` (scheme XML only, no EditorConfig key):

```diff
 base "HTML indent_size = 2", value true:
   <style>
-      body {
-          margin: 0;
-      }
+    body {
+      margin: 0;
+    }
   </style>
```

On base "CSS and JavaScript indent_size = 2", the HTML-indent-4 Default puts `<style>` at 4 and `body {` at 6 (the CSS indent of 2), and `true` moves it to 8.

**Each line is written with the Embedded Language's tab Options.** `html/indent_style.json`, value `tab`: `<style>` and `<script>` lines start with one tab. Their body lines start with 8 spaces (`        body {`), because CSS and JS still use spaces. The record says the same: "The content of `<style>` and `<script>` keeps being indented with spaces beyond the tag's own tab". With `indent_size = 8` + tab, `<style>` gets two tabs and `body {` 12 spaces.

**Host Options can stop the body's indent, but they do not stop the formatting inside.** `html/ij_html_keep_whitespaces.json`, value `true`, `script_style.html`: "`<script>` and `<style>` content is still formatted by the CSS / JavaScript formatters but is not indented relative to the tag":

```html
<style>
body {
    margin: 0;
}

.a {
    color: red;
}
</style>
```

In the source, Keep white spaces makes the Gap between the start tag and the body read-only ([I2] L411–422). So the body's first line keeps its source position, which is column 0 in this input.

`html/ij_html_do_not_indent_children_of_tags.json`, value `""`, `script_style.html`: `<head>` moves in by 4, and the whole `<style>`/`<script>` bodies move with it, again 4 from their tags. The list did not contain `script` or `style` in any run. The source would make such a body start at the tag's column (`HtmlPolicy.indentChildrenOf` → `XmlTagBlock.getChildrenIndent`, [I8] L37–58, [I2] L322–326), but this is not recorded.

**Other Options inside are the Embedded Language's.** In the Default output of `script_style.html`, the CSS formatter expanded `.a { color: red; }` to three lines and put one blank line between the rules. The JS body was re-indented. `<script type="text/template">` content (`<div>template</div>`) was indented as HTML. `<script type="text/babel">` goes to the JavaScript (JSX) formatter: the HTML quote Options even rewrite its JSX attributes (`html/ij_html_enforce_quotes.json`, `html/ij_html_quote_style.json`). The attribute values `style="color:red;margin:0"` and `onclick="foo(a+b)"` were not touched in any HTML record. A one-line `<script>…</script>` stays on one line (`misc.html`; Blade `nesting.blade.php` `@push`).

## 4. Case 2: Vue

Eight Vue records have inputs with `<script>`/`<style>`. The Vue formatter is open source [V1].

**Top level.** `VueBlock` uses `VueRootFormattingPolicy`, whose `indentChildrenOf` is true only for tags in "Indent children of top-level tag" (default `template`) ([V1] `VueRootFormattingPolicy.kt` L19–28). Nested template tags use `VueHtmlTagBlock`/`VueHtmlBlock`. These blocks follow the HTML policy and report `HTMLLanguage` as their language ([V1] `VueTagBlock.kt` L25–28, `VueHtmlTagBlock.kt` L29–31). So HTML Options act inside the template. A scratch probe in the corpus confirms this ("the HTML code style options act on .vue templates unchanged", `vue-template/indent_size.json` notes). The probe is not part of the record matrix.

**Default: one Vue indent for everything; script and style bodies at column 0.** `lang_blocks.vue`, Default output:

```vue
<template>
  <section>
    <p>text</p>
  </section>
</template>
<script setup lang="ts">
const a: number = 1

function f() {
  return a
}
</script>
<style scoped lang="scss">
.a {
  .b {
    color: red;
  }
}
</style>
<i18n>
{
"en": {
...
```

The TypeScript formatter added the blank line before `function`, and the body uses the Vue indent 2. `<i18n>` has no formatter and keeps its text.

**"Specific to the language in the block"** (`VueCodeStyleSettings.UNIFORM_INDENT.json`, value `false`): the template moves to the HTML indent 4 and `return a` to the TS indent 4. The SCSS body keeps 2, which is the SCSS default. With the HTML/JS/TS/CSS/SCSS indents at 8, all three parts move to 8 per level, whatever the Vue indent.

**"Indent children of top-level tag"** (`ij_vue_indent_children_of_top_level.json`, value `template,script,style`): the bodies move one level in, by the indent of their part's Options:

```diff
 <script setup lang="ts">
-const a: number = 1
+  const a: number = 1
 ...
 <style scoped lang="scss">
-.a {
-  .b {
+  .a {
+    .b {
```

With `uniform_indent = false`, the same value puts the script body at 4 (TS) and the style body at 2 (SCSS).

**Interpolations `{{ }}` are formatted in the IDE only.** All three Vue interpolation wrap Options are `untestable-via-cli`: "Acts only on the injected JavaScript expression of an interpolation, which the command-line formatter does not format". The spaces Option `ij_vue_spaces_within_interpolation_expressions` has the same status. A GUI run (`tests/gui/vue/`, 19 files; `docs/notes/BEHAVIOR-GUI-1.md` §1) gives this, with `max_line_length = 60`:

```vue
<!-- input.vue -->
<span>{{a+b}}</span>
<span>{{ fn( 1,2 ) }}</span>
<span>{{ someFunctionName(argumentNumberOne, argumentNumberTwo, argumentNumberThree) + anotherValue }}</span>
<!-- base_nosetting.vue (no ij_vue_* key) -->
    <span>{{ a + b }}</span>
    <span>{{ fn(1, 2) }}</span>
    <span>{{
        someFunctionName(argumentNumberOne, argumentNumberTwo, argumentNumberThree) + anotherValue
      }}</span>
```

The source explains the parts:

- `VueExprFormattingModelBuilder` builds the expression's root Block with `Wrap(INTERPOLATION_WRAP)` and `Indent.getNormalIndent()`, and it wraps the root "to add indentation" ([V2] L29–39). So the expression is at the `<span>` content level + one level. With Vue indent 2, the `<span>` is at 4, its content at 6, and the expression at 8.
- `VueSyntheticBlock.getSpacing` puts 1 or 0 spaces between `{{`/`}}` and the expression ("Interpolations" in Spaces). It gives a line feed that depends on the expression's lines for "New line after `{{`" / "New line before `}}`" ([V1] L28–58).

The corpus says that the rule for when a source line break is kept "was not worked out".

**Directive values are not formatted.** In the command-line outputs, `:title="a+b"` and `@click="go( a,b )"` stay as written (cached Default outputs of `spaces/interpolations.vue` and `spaces/r2_script_setup_ts.vue`, `work/formatter-vue/cache/c9fa479e8da8521ac2a4.json`). The open source agrees (read-only attribute values, §1). No IDE run exists.

## 5. Case 3: Blade (and Twig for comparison)

PhpStorm treats Blade as a template. The Blade indent applies to HTML tags and to Blade directive blocks. The HTML indent Options are "ignored for Blade files" (`blade/html.indent_size.json`, `blade/indent_size.json`). That is the ADR-0005 rule. Within it there are three kinds of embedded code:

**`<script>` and `<style>`: the CSS/JS indent, from the tag.** The cached outputs behind `blade/HtmlCodeStyleSettings.HTML_UNIFORM_INDENT.json` (all diffs empty; the record keeps no output) show this, with "Blade indent_size = 2 + CSS and JavaScript indent_size = 8" (`work/formatter-markup-fix/cache/868c01aecf706fd66456.json`):

```html
<head>
  <style>
          body {
                  margin: 0;
          }
  </style>
  <script>
          function f(a, b) {
                  if (a) {
```

The `<script type="text/template">` content uses the Blade indent: with Blade indent 2, `<div>template</div>` is at the tag + 2 (`…/67f7a6cd4e09192e660a.json`). Twig gives the same output with "Twig indent_size = 2 + CSS and JavaScript indent_size = 8" (`…/5511570d198f511704e4.json`). Checking "Use HTML indents within `<style>` and `<script>`" changes nothing in either. The record's note says why: the field is read only by `HtmlFileIndentOptionsProvider`, which applies only to HTML-kind file types.

**`<?php … ?>`: formatted with the PHP Code Style, one PHP indent inside its HTML parent.** `blade/php.indent_size.json`, `php_inside.blade.php`, value `2`:

```html
<div>
  <?php
  if ($y) {
    echo $y;
  ...
  ?>
    @php
        $z=1;
```

The `<?php` block moved from 4 to 2 inside `<div>`, but the Blade sibling `@php` stayed at 4 (the Blade indent). With value `8` the `<?php` block is at 8. PHP spaces Options act only here (`blade/php.space_around_additive_operators.json`, `blade/php.space_around_assignment_operators.json`). A blank line inside the block keeps its indent only when both Blade's and PHP's "Keep indents on empty lines" are on (`blade/php.keep_indents_on_empty_lines.json`).

**`{{ }}`, `{!! !!}`, directive arguments, `@php … @endphp`: not formatted.** The `php.indent_size` note says: "PHP code in `{{ }}`, `{!! !!}`, in directive arguments … and in `@php` … `@endphp` is left exactly as written … only the lines of `@php` get the Blade block indent. Only the `<?php ... ?>` block is formatted by the PHP code style." `{{ $a+$b }}` and `@if($a&&$b)` keep their spacing in every run on `php_inside.blade.php`. Blade's own spaces Option is not read (`blade/blade.space_around_assignment_operators.json`, no-visible-effect). In `nesting.blade.php` every line of a `@php` body goes to the block's indent. All those input lines were at column 0, so we cannot tell whether relative indents inside are kept. In PhpStorm these pieces are most likely PHP injections (not checked, the Blade plugin is closed). If so, the command-line caveat applies again.

## 6. Case 4: PHP heredoc and nowdoc

PhpStorm injects a language into a heredoc or nowdoc whose marker is a language ID (`<<<SQL`, `<<<HTML`), or by a `// language=<ID>` comment [P1]. The corpus has one injected heredoc: `<<<SQL` in `tests/formatter/php/tabs_and_indents/heredoc_and_comments.php`. No PHP Option in the corpus is about injections (`data/catalog.json`, `data/searchable-options.json`).

- **The injected body is never reformatted.** In all 56 outputs of `heredoc_and_comments.php` across 5 records (`php/indent_size.json`, `indent_style.json`, `tab_width.json`, `ij_continuation_indent_size.json`, `ij_php_indent_code_in_php_tags.json`), the body and the closing marker stay at 8 spaces. The statement moves:

  ```diff
   php/indent_size.json, value 2:
  -    $sql = <<<SQL
  +  $sql = <<<SQL
           SELECT *
           FROM table
           SQL;
  ```

- **PHP only moves the body as one unit.** "Place on the same line as variable declaration" (`php/ij_php_heredoc_on_same_line.json`, value `true`) puts each body line and the closing marker of assigned and returned heredocs one level deeper than the statement (`    $a = <<<EOT` / `        body` / `        EOT;`). It leaves call arguments and array values alone. No other record changes a heredoc body (58 changed heredoc-file outputs checked).
- This is safe for the program: since PHP 7.3, the closing marker's indent is removed from every body line, so moving the body and the marker together keeps the string's value. Reformatting the Embedded Language inside the body would change the string.
- Whether the IDE's Reformat Code formats `<<<HTML` or `<<<SQL` bodies is not known. The PHP formatter is closed, and the command-line formatter skips injections. PhpStorm's documented way to format an injected fragment is "Edit `<language>` Fragment", whose editor "provides … code style actions" [P1].

## 7. How the Tree-sitter trees look in Neovim

Neovim parses each injection region into a child `LanguageTree` of the host. There is one child per language. A non-combined match becomes its own region set, and so its own `TSTree`. A combined pattern collects all its matches into one region set ([N1] `add_injection`, L978–1012). The injection language is lower-cased and resolved to a parser or filetype, and it is dropped when no parser exists (`resolve_lang`, L1024–1044). Node positions of injected trees are buffer-absolute.

Local run ([E1]; nvim-treesitter `main` queries; parsers built at the revisions that nvim-treesitter pins, except `html`, `javascript` and `typescript` from the user's site directory). The ranges are `row:col-row:col`, 0-based:

```
### a.html                                   (<style>, <script>, <script type="module">, <a onclick= style=>)
html: 1 tree(s)
  javascript: 3 tree(s) {4:8-6:0} {7:22-9:0} {10:12-10:17}     ← the third is onclick="go(1)"
  css: 2 tree(s) {1:7-3:0} {10:26-10:35}                        ← the second is style="color:red"
### a.vue
vue: 1 tree(s)
  javascript: 1 tree(s) {6:8-8:0}                                ← <script> without lang
  typescript: 5 tree(s) {1:15-1:18} {1:26-1:28} {1:38-1:43} {1:47-1:52} {3:24-5:0}
                                                                 ← :title, v-if, @click, {{ }}, <script setup lang="ts">
  css: 1 tree(s) {9:18-11:0}
### a.blade.php
blade: 1 tree(s)
  javascript: 1 tree(s) {7:12-9:4}
  php_only: 3 tree(s) {1:8-1:10} {2:14-2:17} {5:8-6:4}          ← @if($a), {{ $b }}, @php body
### b.blade.php
  php_only: 3 tree(s) {1:6-1:32} {3:0-4:0} {5:3-5:9}            ← <?php … ?>, @php body, {{ }}
### b.php                                    (inline HTML with <script>, plus <<<HTML heredoc with <script>)
php: 1 tree(s)
  html: 2 tree(s) {0:0-1:0 2:0-5:0 6:0-7:0} {8:12-9:34}         ← combined template tree + separate heredoc tree
    javascript: 2 tree(s) {2:8-4:0} {9:11-9:21}
```

Blade tree shape on `main` (tree-sitter-blade extends tree-sitter-html, [N4] L27–31, L387–412):

```
(document (element (start_tag (tag_name))
  (conditional (directive_start) (parameter) (element … (php_statement (php_only)) …) (directive_end))
  (php_statement (directive_start) (php_only) (directive_end))
  (script_element (start_tag (tag_name)) (raw_text) (end_tag (tag_name))) …))
```

What this implies for Blocks:

- **Every non-template case is a graft into one host leaf.** The host leaf is `raw_text` (script/style, Vue interpolation), `attribute_value`, `php_only`/`parameter` (Blade), or `heredoc_body`/`nowdoc_body`. The embedded tree covers that leaf's range, so its Blocks replace the leaf. Nothing crosses. This is the case that ADR-0005 calls "simpler" for Vue and Blade.
- **Regions include the whitespace around the code.** `raw_text` starts after `>` with the newline and ends with the indent before `</script>`; for example `{7:12-9:4}` ends at column 4 of the `</script>` line. Leaf ranges need trimming, as in ADR-0005.
- **Positions need no translation.** The embedded nodes already carry buffer offsets, unlike IntelliJ's `InjectedLanguageBlockWrapper`, which shifts by a prefix ([I7] L30–78). Blade `<?php … ?>` regions exclude the tags, so the PHP Language Plugin sees no `php_tag`. It must know that it formats a fragment.
- **The user's queries choose other languages than PhpStorm.** Run [E1] (`types.lua`) and the `html_tags`/`vue` queries [N2] show:
  - `type="text/babel"`, `type="text/template"`, `type="application/ld+json"` and `lang="ts"` in HTML get no injection. The `#gsub!` yields `babel`, `template` and `ld+json`, which have no parser, and `lang=` is excluded on purpose so that Vue can add it.
  - Only `type="module"`, plain `<script>`, `type="text/javascript"` and `importmap` (JSON) are injected.
  - Attribute values `style=` and `on*=` and lit-html `${}` are injected, and the Blade query injects Livewire/Alpine attributes too. PhpStorm leaves attribute values alone.
  - Vue `{{ }}` and every `directive_attribute` value are injected as `typescript`, even in a JS component.
  - `<style lang="less|sass|postcss">` is injected as `scss`.
  - Heredoc labels: `HTML` and `SQL` resolve, but `JS` does not, because `get_lang('js')` returns `js`, which has no parser.
- **The shape depends on the nvim-treesitter branch.** On `master` (`cf12346`), Blade injects `text` as one combined `html` tree and `php_only` as one combined tree [N3]. That is a template layout, like Twig. ADR-0002 already says that a Language Plugin cannot fix the user's parser version. The research for #3 recommends pinned parsers loaded with `vim.treesitter.language.add`.
- **The Core can supply its own injection query.** `LanguageTree` reads `opts.injections[lang]` before `query.get(lang, 'injections')` ([N1] L118, L139–149). `get_parser` and `get_string_parser` pass `opts` through. This lets the Core parse with embed points that the Language Plugins declare, not the user's queries. The `injections` field is not described in `:help` for `get_parser`.

## 8. Contrast with the template merge (ADR-0005)

| | Template (ADR-0005: PHP with inline HTML, Twig; Blade in PhpStorm) | Not a template (`<script>`/`<style>`, Vue parts, Blade `<?php ?>`, injections) |
|---|---|---|
| Tree relation | Two trees decide each other's indent and interleave. The HTML tree spans the host's tags. | The embedded tree lies inside one host leaf. |
| Block step | Merge (`TemplateFormatUtil.mergeBlocks`) | Graft (`AnotherLanguageBlockWrapper`) |
| Indent Options | One set for the template layers, chosen by the Host Language (inferred: template Blocks carry no language) | The Embedded Language's own, unless the host overrides (HTML "uniform indent", Vue "Same in the whole file") |
| Offset from the host | Host and HTML nesting levels, all in the same indent | Tag column + one Embedded Language indent (or none, if the host says so) |
| Other Options | Each layer's own language | The Embedded Language's own |
| Gaps at the border | Owned by the lowest Block that holds both leaves | Owned by the host Block that holds the wrapper |

Both follow the same IntelliJ rule (§2). A Block uses its language's indent Options, else the file's; the file can override. The template layers get the file's Options, so they behave as Blocks with no language of their own. This is inferred, because the PHP, Twig and Blade formatters are closed, but the records fit it. Embedded Blocks have a language. A file can be both: a Twig or Blade file is a template, and its `<script>` bodies are embedded parts with their own indent. _Contradicts the wording of ADR-0005 ("One set of indent Options … applies to the whole file"), and is worth refining, because the Twig and Blade records put `<script>`/`<style>` bodies on the CSS/JS indent._ For a PHP file with inline HTML, the corpus has no `<script>` input, so the ADR's "uses HTML's indent Options for all of its lines" is not checked for script bodies.

## 9. What this needs from the Core and the Language Plugins

The constraints are pure Lua on the user's parsers (ADR-0002) and fidelity to the Behaviour Records. Each item below lists the options and their trade-offs.

### 9.1 How the embedded part enters the Block tree

- **A. Graft (port of `AnotherLanguageBlockWrapper`).** The host builder emits an *embed point*: the host leaf, the Embedded Language, and the indent kind (normal, none, continuation). The Core asks the Embedded Language's Language Plugin for Blocks over that range and hangs them under the host Block. The engine then runs once over the whole tree. It is a direct port, so its results can match the records (offset = tag column + embedded indent, leaf-language tab rendering, host-owned border Gaps such as Vue's `{{ }}` spaces, wrapping against one right margin). It costs a Block builder that works on a fragment, and every Block must carry a language.
- **B. Sub-formatter run.** The Embedded Language's plugin formats its range on its own, with a start column that the host computes first. The Core splices the result. The contract is smaller (`format(range, base_indent, options) → edits`). But it needs two passes, and it cannot reproduce effects that cross the border: the Vue `{{` line feed, which depends on whether the expression is multi-line ([V1] `VueSyntheticBlock.kt` L40–50), wrapping against the line's real width, and alignment. Printer-style formatters use this model (Prettier's embed, markup_fmt; see #3).
- **C. Read-only parts.** The merge prototype keeps `<script>` and `<style>` as read-only leaves (`prototype/merge/README.md`). This fails every HTML/Vue/Twig/Blade Default output that re-indents a body. It is acceptable only when the Embedded Language's plugin or parser is missing.

### 9.2 Which language an embed point has

- **User's injection queries** (`LanguageTree:children()`). They cost nothing, and the parse is cached for highlighting. But the language often differs from PhpStorm's choice (§7), attribute values get injections that PhpStorm never formats, and Blade's shape changes between nvim-treesitter branches.
- **Plugin-declared embed points.** The host Language Plugin owns the rule (tag + `type`/`lang` attribute, interpolation, `<?php ?>`, heredoc label), and the Core parses those ranges. It can use `get_string_parser(…, {injections = …})` with a Core-built query, or parse each range with a pinned parser. This matches PhpStorm and is deterministic. The cost is that each host plugin maintains the rules, and `opts.injections` is undocumented.
- **Hybrid.** Use the plugin's rules to pick the language, and reuse the user's child trees when they agree.

### 9.3 Indent Options and line rendering

- **Per-Block language with a host override flag** (port of `BlockIndentOptions`). Every Block has a language or none. Blocks without one use the file's indent Options, which the Host Language's plugin chooses (as in ADR-0005). The host can set "override" (HTML uniform indent, Vue "Same in the whole file"). Each line is rendered with the indent and tab Options of its leaf's language. This one rule covers ADR-0005, HTML, Vue, Twig, Blade and the tab record.
- **Base indent passed to the embedded builder.** This is simpler, but it cannot express "the `<script>` line in tabs, the body in spaces" unless the renderer also knows the leaf's language.

### 9.4 What each Language Plugin supplies

- **Host plugins** (HTML, Vue, Blade, Twig, PHP):
  - the embed points and the indent kind for each (from "Indent children of top-level tag", "Keep white spaces", "Do not indent children of");
  - an optional indent override;
  - the Spacing of the border Gaps (Vue interpolation Options);
  - which parts stay read-only (attribute values, Blade `{{ }}`/`@php` bodies, heredoc bodies).
- **Embedded plugins** (JS/TS, CSS/SCSS, PHP):
  - a Block builder for a range that is not a whole file;
  - rules that do not assume the file start;
  - an entry for a fragment without its own tags, such as Blade `<?php ?>` regions without `php_tag`, and Vue expressions.
- **Plugins that build on HTML.** Vue and Blade grammars extend tree-sitter-html, so their HTML nodes have HTML's node types. Vue and Blade also read HTML's Options: Blade has 23 verified-effect "Inherited HTML settings" records, and Vue copies HTML's common settings. So the contract must let a plugin reuse the HTML plugin's rules (by composition) and read another language's Options. IntelliJ does this by subclassing (`VueBlock extends XmlBlock`), which our design rules exclude.
- **A missing Embedded Language plugin or parser** (Less/Sass in Vue, `<i18n>`, `text/babel` without a JSX parser): the part is one read-only leaf. Its lines keep their text, as in ADR-0002 and IntelliJ's `useMyFormatter` path. Only the Gap before it moves with the host. The records show the kept text (`<i18n>`). They do not show a nested missing-plugin part whose host moves.

## 10. Gaps and open questions

- **No IDE run for most injections.** The records come from the command-line formatter, which skipped the Vue interpolation expressions. Blade `{{ }}`/`@php`, Vue directive values, HTML `style=`/`on*=` values and `<<<HTML`/`<<<SQL` bodies were never checked in the IDE.
- **`<script>`/`<style>` in a `.php` file with inline HTML:** JS/CSS indent or HTML indent? No input.
- **No record varies a JS/TS/CSS/SCSS Option on an HTML or Vue input.** The right margin inside an embedded part is known from the source only.
- **Not recorded:** "Do not indent children of" or "or if tag size more than" applied to `script`/`style`.
- **Relative indents inside unformatted bodies** (`@php` lines, heredoc bodies) were not seen. Every input line was at the same column.
- **The Vue interpolation line-break rule** (keep or remove a source break) is unexplained in the corpus.
- **Blade quirks:** the wrapped continuation lines of the JSX tag in `<script type="text/babel">` are 4 columns deeper in Blade than in HTML (`docs/languages/blade.md`, notes on `ij_html_align_attributes`). Not explained.

## Method

- Behaviour Records were read with a small script that prints the inputs, base outputs and per-value diffs of a record. They were counted with Python over `data/behavior/*/*.json`. The cached outputs of empty-diff runs were found by matching the scheme in `work/*/cache/*.json` (the run cache that `tools/behavior/rebuild_cached.py` reads).
- IntelliJ files were fetched from `raw.githubusercontent.com` at tag `idea/262.10968.63`. GitHub code search found where `HTML_UNIFORM_INDENT`, `UNIFORM_INDENT` and `INTERPOLATION_WRAP` are read.
- Tree shapes [E1]: `nvim --headless -u NONE -l trees.lua`. The runtime path is only nvim-treesitter's `runtime/` and `$VIMRUNTIME`, because a copy of the queries in the user's `site/` doubled every match. Each grammar is loaded with `vim.treesitter.language.add`, and `LanguageTree:parse(true)` runs on small samples. The script prints each `LanguageTree`'s language, its number of trees and `included_regions()`, then recurses over `children()`. `types.lua` does the same for six `<script>` variants.

## Sources

- [C] Research Corpus `~/Projects/phpstorm-editorconfig/` (PhpStorm 2026.2.3): `README.md`; `data/behavior/{html,vue-template,blade,twig,php}/*.json` (named in the text); `docs/languages/{html,vue-template,blade,twig,php}.md`; `docs/notes/BEHAVIOR-NOTES.md` (statuses); `docs/notes/BEHAVIOR-GUI-1.md` §1; `tests/gui/vue/` (`input.vue`, `base_nosetting.vue`, `spaces_false.vue`, …); `tests/formatter/{html,vue-template,blade,php}/`; run caches `work/formatter-markup-fix/cache/{868c01aecf706fd66456,67f7a6cd4e09192e660a,ff0bba673f9c4ee5abf3,5511570d198f511704e4,1531d994f40a5c5539fc,887d7e26909eb07d4c1c}.json`, `work/formatter-vue/cache/c9fa479e8da8521ac2a4.json`.
- [I1] `AbstractXmlBlock.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/xml/xml-ui-common/src/com/intellij/psi/formatter/xml/AbstractXmlBlock.java
- [I2] `XmlTagBlock.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/xml/xml-ui-common/src/com/intellij/psi/formatter/xml/XmlTagBlock.java
- [I3] `XmlBlock.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/xml/xml-ui-common/src/com/intellij/psi/formatter/xml/XmlBlock.java
- [I4] `AnotherLanguageBlockWrapper.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/xml/xml-ui-common/src/com/intellij/psi/formatter/xml/AnotherLanguageBlockWrapper.java
- [I5] `InjectedLanguageBlockBuilder.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/platform/code-style-impl/src/com/intellij/psi/formatter/common/InjectedLanguageBlockBuilder.java
- [I6] `XmlInjectedLanguageBlockBuilder.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/xml/xml-ui-common/src/com/intellij/psi/formatter/xml/XmlInjectedLanguageBlockBuilder.java
- [I7] `InjectedLanguageBlockWrapper.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/platform/code-style-impl/src/com/intellij/psi/formatter/common/InjectedLanguageBlockWrapper.java (`DefaultInjectedLanguageBlockBuilder.java` in the same folder is the non-XML variant)
- [I8] `HtmlPolicy.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/xml/xml-ui-common/src/com/intellij/psi/formatter/xml/HtmlPolicy.java
- [I9] `HtmlFileIndentOptionsProvider.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/xml/xml-ui-common/src/com/intellij/psi/formatter/xml/HtmlFileIndentOptionsProvider.java
- [I10] `BlockIndentOptions.java`, `AbstractBlockWrapper.java`, `IndentAdjuster.java`: https://github.com/JetBrains/intellij-community/tree/idea/262.10968.63/platform/code-style-impl/src/com/intellij/formatting (`engine/` for the first and third)
- [I11] `CommonCodeStyleSettings.java` (`IndentOptions.setOverrideLanguageOptions`): https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/platform/code-style-api/src/com/intellij/psi/codeStyle/CommonCodeStyleSettings.java
- [I12] `CodeFormatterFacade.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/platform/code-style-impl/src/com/intellij/psi/impl/source/codeStyle/CodeFormatterFacade.java; `InjectedFormattingOptionsProvider.java`: https://github.com/JetBrains/intellij-community/blob/idea/262.10968.63/platform/code-style-api/src/com/intellij/formatting/InjectedFormattingOptionsProvider.java
- [V1] Vue formatter, `vuejs/vuejs-backend/src/org/jetbrains/vuejs/lang/html/psi/formatter/` (`VueFormattingModelBuilder.kt`, `VueBlock.kt`, `VueTagBlock.kt`, `VueHtmlBlock.kt`, `VueHtmlTagBlock.kt`, `VueSyntheticBlock.kt`, `VueRootFormattingPolicy.kt`, `VueFileIndentOptionsProvider.kt`, `VueCodeStyleSettings.kt`): https://github.com/JetBrains/intellij-plugins/tree/idea/262.10968.63/vuejs/vuejs-backend/src/org/jetbrains/vuejs/lang/html/psi/formatter
- [V2] `VueExprFormattingModelBuilder.kt`: https://github.com/JetBrains/intellij-plugins/blob/idea/262.10968.63/vuejs/vuejs-backend/src/org/jetbrains/vuejs/lang/expr/psi/formatter/VueExprFormattingModelBuilder.kt
- [N1] Neovim 0.12.6 `runtime/lua/vim/treesitter/languagetree.lua` (`LanguageTree.new` opts L118–149, `children` L400, `add_injection` L978–1012, `resolve_lang` L1024–1044, `_get_injection` L1050–1078) and `:help treesitter-language-injections`, `:help vim.treesitter.get_parser()`: https://github.com/neovim/neovim/blob/v0.12.6/runtime/lua/vim/treesitter/languagetree.lua
- [N2] nvim-treesitter `main` @ `a2f6944`: `runtime/queries/{html_tags,html,vue,php,php_only,blade,twig}/injections.scm`, `lua/nvim-treesitter/parsers.lua` (pinned revisions): https://github.com/nvim-treesitter/nvim-treesitter/tree/main/runtime/queries
- [N3] nvim-treesitter `master` @ `cf12346`: `queries/{blade,php_only,html_tags}/injections.scm`: https://github.com/nvim-treesitter/nvim-treesitter/tree/master/queries
- [N4] tree-sitter-blade @ `b5291d1` `grammar.js`: https://github.com/EmranMR/tree-sitter-blade
- [P1] PhpStorm 2026.2 Help, "Language and reference injections": https://www.jetbrains.com/help/phpstorm/using-language-injections.html
- [E1] Local headless runs, 2026-10-31, Neovim 0.12.6 (§7 and "Method").
- ADRs: `docs/adr/0002-pure-lua-engine-on-users-tree-sitter.md`, `docs/adr/0005-template-files-merge-block-trees-like-intellij.md`. Related research: `docs/research/engine-building-blocks.md` on branch `research/engine-building-blocks` (#3). Merge prototype: branch `prototype/merge` (#19).
