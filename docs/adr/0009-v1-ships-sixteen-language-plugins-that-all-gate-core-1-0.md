# v1 ships sixteen Language Plugins, and all of them gate Core 1.0

Core 1.0 is released only when each of these sixteen first-party Language Plugins passes its Behaviour Records: HTML, PHP, CSS, JavaScript, TypeScript, Twig, Blade, Vue, SCSS, XML, JSON, YAML, Markdown, EditorConfig, Shell Script and Makefile. General is not a Language Plugin. It ships with the Core as the reserved `general` id (ADR-0003). Every plugin is its own repo, made from one durable Language Plugin template repo that third parties use too. The Research Corpus languages that are left out are left out because nothing in Neovim lets us match PhpStorm for them ("Which Research Corpus languages ship in v1?", #13).

## Considered Options

- **A small launch set that gates 1.0, and a later set on the same contract version.** 1.0 would come sooner, but the operator wants the whole list at 1.0.
- **Core 1.0 with no Language Plugin as a gate.** The contract would not be proven by real plugins before it is frozen at `api` 1.

## Consequences

- **Out of v1:** SQL (its grammar fails on 61% of test inputs, and it has 11 dialects); Less, Sass and Gherkin (nvim-treesitter has no parser for them, ADR-0002); Angular HTML template (its grammar fails on every Preview); Mermaid and HTTP Request (weak grammars); Other File Types (its Options act only while typing). Each can return only as a new effort.
- **SCSS is in, but Less and Sass are out**, although all three share CSS's rules. SCSS has an nvim-treesitter parser. Its grammar fails on every Preview, so the SCSS Options that it cannot parse are flagged.
- **Shell Script runs the user's `shfmt`**, the narrow exception in ADR-0002.
- **Makefile is the one language with no PhpStorm reference.** PhpStorm's Makefile plugin has no formatter, so Reformat leaves a Makefile unchanged, and there are no Behaviour Records. On the operator's decision, our Reformat uses the three Makefile Options with our own rules: recipe lines always keep their leading tab, and only directive bodies (`ifeq`/`else`/`endif`) and continuation lines are re-indented. This is the one exception to the fidelity rule, and the Makefile plugin marks it as such.
- **Build order:** the Core and the template repo, proven end to end with JSON as a small tracer; then PHP (Arrangement, Presets, the LSP path); then HTML and the template merge; then CSS and JavaScript (grafts); then TypeScript; then Twig, Blade and Vue (`uses = { html = … }`); then SCSS, XML, YAML, Markdown and EditorConfig; then Shell Script and Makefile.
- **Each language family is specified in its own map:** PHP; HTML (HTML, Twig, Blade, Vue); JS (JavaScript, TypeScript); CSS (CSS, SCSS); small languages (JSON, YAML, XML, Markdown, EditorConfig, Shell Script, Makefile).
