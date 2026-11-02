# Arrangement is a Core engine over the entries that plugins find

Arrangement has one shape in all eight PhpStorm rearrangers: rule aliases, "Keep … together" rules, and an ordered list of slots that hold matching rules. So the Core owns one Arrangement schema and one engine, a port of IntelliJ's `ArrangementEngine` (match, sort, Keep-Together Rules, moving the text). A Language Plugin only finds the Arrangement Entries in a buffer and declares its vocabulary as data. The engine is tested once by the 605 Arrangement cases ("What is the Arrangement model?", #28).

## Stored shape

`languages.<id>.arrangement` is a key that the Core reserves next to the Options. It is not an Option, so the six Option types of ADR-0003 stay closed. The value is stored whole, and only when it differs from the plugin's default, as PhpStorm writes `<arrangement>` only when it differs.

```json
"arrangement": {
  "enabled": false,
  "aliases": { "visibility": [ { "is": ["public"] }, { "is": ["protected"] }, { "is": ["private"] } ] },
  "keep_together": [ { "kind": "getters_setters", "order": "keep" } ],
  "slots": [
    [ { "is": ["const"] } ],
    [ { "is": ["field"], "alias": "visibility" } ],
    [ { "is": ["method"], "is_not": ["static"], "name": "get.*", "order": "by_name" } ]
  ]
}
```

- A rule is one AND of conditions: `is` and `is_not` (entry types and modifiers), `name` and `namespace` (regexes), `alias`, and `order` (`keep` or `by_name`). PhpStorm's rule editor produces only this, and the Research Corpus has no `<OR>`, so we store no match tree (ADR-0003: store what the UI can produce).
- Regexes use Vim syntax. The Core anchors them for a full match and makes them case-sensitive, as PhpStorm does.
- `enabled` is true by default and appears in the Menu as "Rearrange when formatting".
- A Slot has no start/end comment text in v1, because no Behaviour Record tests it.

## Considered Options

- **A seventh Option type, or a top-level `arrangement` map.** Rejected: the first opens ADR-0003's closed set, and the second splits one language's Code Style in two places.
- **A full AND/OR match tree.** Rejected: PhpStorm's UI never shows one, and the rule editor would have to edit a tree.
- **A plugin that does all the work** (`arrange(ctx)` → edits). Rejected: eight plugins would repeat the matching, sorting and moving.
- **Java regexes as PhpStorm writes them**, translated or run by a Lua engine. Rejected by the operator in favour of Vim syntax, which `vim.regex` runs directly.
- **Arrangement off by default in a format run**, as in PhpStorm's Reformat Code. Rejected by the operator: a format run rearranges first, and each language's `enabled` flag turns that off.

## Consequences

- **The spec** (data, ADR-0007) gets an `arrangement` table: the entry types, modifiers and Keep-Together kinds, whether `name` and `namespace` apply, the default Arrangement, and a `phpstorm` map from PhpStorm token ids to its own ids (`FIELD = 'field'`). The Menu's Arrangement editor reads it too (ADR-0012). So reading the file and opening the Menu load no code.
- **The `arrangement` module** (code) has `entries(ctx)`, which returns a tree of Arrangement Entries made with Core constructors: range (with the comments and doc blocks that travel with the entry), types, modifiers, name, namespace, children, and the links that Keep-Together Rules need (getter/setter pairs, calls). An optional `blank_lines` is the port of IntelliJ's `getBlankLines`.
- **Format runs:** while `enabled` is true, every format run rearranges first (ADR-0002). `:Codestyle arrange` always rearranges. `codestyle.testing` turns Arrangement off for the formatter Behaviour Records, which PhpStorm's command-line formatter made without rearranging.
- **Selection:** only entries that intersect `ctx.range` take part, and they move only among themselves (IntelliJ's `isWithinBounds`). No Behaviour Record tests this.
- **Embedded parts:** at each Embed Point (ADR-0008), the Core calls the embedded language's `entries` and applies that language's Arrangement and `enabled`. The part is one opaque entry of the host, so entries never cross it. With no plugin for that language, the part is not rearranged.
- **"Overridden" features** (the `overridden` modifier and the overridden-methods Keep-Together Rule): `entries` looks for parents only when the Arrangement uses them. Parents in the same file come from the parse tree. Parents in other files come from `ctx.lsp` (`typeHierarchy/supertypes`, then `documentSymbol`), called synchronously within one time budget per run. With no client, an unsupported method or a timeout, `overridden` matches nothing and the rule is skipped, with one warning per run (ADR-0002).
- **Scheme XML import:** the Core, not the module, converts `<arrangement>` through the spec's `phpstorm` map, and it converts Java regexes to Vim syntax. The import report lists what it could not import: `<OR>` or nesting, unknown tokens and Keep-Together kinds, regexes it cannot convert, and Slot comment text. A language whose XML has no `<arrangement>` gets the default (ADR-0010).
- **Invalid stored Arrangement** (an unknown token, a bad regex, a broken shape): the whole default is used, with one warning that names the bad part. The raw value stays in the file until the user edits the Arrangement in the Menu (ADR-0003). Token renames go through the plugin's migrations (ADR-0007).
- **PhpStorm quirks:** the unstable by-name sort of CSS for equal property names is ported. The CSS bug where a moved declaration with no trailing `;` loses its separator is fixed instead. Its records are expected failures in `codestyle.testing`.
- Presets never touch Arrangement (ADR-0006).
