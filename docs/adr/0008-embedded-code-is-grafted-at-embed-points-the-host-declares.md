# Embedded code is grafted at Embed Points that the host Language Plugin declares

The host Language Plugin's Block builder returns each Embed Point: the host leaf, the Embedded Language id, the indent kind, the fragment kind, and whether it is a template layer (merged, ADR-0005) or a graft. The Core parses each range with the Embedded Language's own parser, asks that language's Language Plugin for Blocks with `build(ctx)` (where `ctx.fragment` names the kind, such as `script` or `php_region`), and hangs them under one host Block, as IntelliJ's `AnotherLanguageBlockWrapper` does. The user's injection queries never decide formatting, because they pick other languages than PhpStorm: `text/babel` and `lang="ts"` in HTML get no injection, `style=` and `on*=` values do, Vue expressions become `typescript`, and Vue `<style lang="less">` is parsed as `scss` ("How is embedded code that is not a template formatted?", #24). Every Block carries a language, and indent Options are resolved per Block, as in IntelliJ's `BlockIndentOptions`. Template-layer Blocks use the file's indent Options, which the Host Language chooses. Grafted Blocks use their own language's. A host can set an override, and then every Block uses the file's Options. Only this rule reproduces the records: `<script>` and `<style>` bodies use the JS and CSS indent in HTML, Twig and Blade, and HTML's "Use HTML indents within `<style>` and `<script>`" and Vue's "Same in the whole file" switch them to the file's indent ("What is the Language Plugin contract?", #12).

## Considered Options

- **The user's injection trees.** No extra parse, but the output would depend on the user's queries and nvim-treesitter branch, and would differ from PhpStorm.
- **A sub-formatter run per range with a base indent.** A smaller contract, but it cannot reproduce effects that cross the border: Vue's line break after `{{`, which depends on the expression, wrapping against the real line width, and alignment.
- **Read-only parts**, as in the merge prototype. They fail every Default output that re-indents a `<script>` or `<style>` body.
- **One set of indent and tab Options per file.** It cannot write the `<script>` line with a tab and its body with spaces, which the HTML records show.

## Consequences

- Each line's whitespace is written with the indent and tab Options of the line's first leaf Block. The host owns the Gaps at the borders of a grafted part, such as the spaces inside Vue's `{{ }}`.
- When the Embedded Language has no Language Plugin or no parser, or its builder returns nil for the fragment kind, the part becomes one read-only leaf. Its lines keep their text, and only the Gap before it moves. One warning per buffer and language, and once per session for a missing plugin. An `ERROR` or `MISSING` node inside a part keeps only its own text, as in a whole file (ADR-0002).
- Parts that PhpStorm leaves alone (attribute values, Blade `{{ }}` and `@php` bodies, heredoc bodies) are not Embed Points. The host builder makes them read-only Blocks, and they give no warning.
- Whether `<script>` and `<style>` in a `.php` file with inline HTML use the JS and CSS indent is not recorded. "What does the PhpStorm IDE do to embedded code that the records cannot show?" (#26) checks it.
