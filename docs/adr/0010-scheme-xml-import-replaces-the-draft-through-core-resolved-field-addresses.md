# Scheme XML import replaces the Draft through Core-resolved field addresses

A Scheme XML import writes into the Draft of the Code Style that is being edited, as one undo step, and nothing reaches the file until the user saves. Unlike a Preset (ADR-0006), the import replaces: `general` and every installed language are reset to their defaults, and then the XML values are applied. PhpStorm writes only non-default values, so an absent field means "default", and only a replace formats exactly like the IDE. The Core reads the XML with its own strict Lua reader and resolves each field address that a Language Plugin's `scheme` module names. So the plugins share one mapping that the import and the golden tests both use ("How is Scheme XML imported into a Code Style?", #17).

## Considered Options

- **Merge, as a Preset does.** Rejected, because values left over from before the import would stay wherever PhpStorm meant "default".
- **Write the file at once.** Rejected for the Draft, where the Preview shows the result before the save, and undo works.
- **Store the raw fields of languages with no installed plugin** in the file, and convert them when the plugin is installed. Rejected, because unvalidated values would reach the file (ADR-0006), and PhpStorm field names would become part of our file format.
- **The user's Tree-sitter `xml` parser.** It is a full XML 1.0 grammar, but the import would then depend on a parser that only the XML Language Plugin needs, and its error recovery would accept a broken file without a word.
- **Plugins that read the raw XML tree.** Rejected, because every plugin would repeat the lookup and conversion, and the golden tests would have no common mapping.
- **Follow `codeStyleConfig.xml` to an IDE scheme** in the PhpStorm config directory. Rejected by the operator: we have our own store, so the import reads only what the user gives it.

## Consequences

- **Sources:** only `.idea/codeStyles/Project.xml` when the repo has it, otherwise a path that the user gives. The Core never reads `codeStyleConfig.xml` or IDE scheme directories.
- **Where to start it:** `i` in the Menu imports into the Code Style that is being edited, Global or Project. `:Codestyle import [path]` opens the Menu and starts the import there. This adds to the import places of ADR-0004.
- **The XML reader:** the Core's reader handles elements, attributes in either quote style, self-closing tags, text, comments, `<?xml?>`, CDATA, the five named entities and numeric references. It rejects DOCTYPE. It unwraps `<component name="ProjectCodeStyleConfiguration">` to reach `<code_scheme>`. On malformed XML, the import stops with one error that gives the line, and the Draft is untouched.
- **What a `scheme` module declares:** its `language=` attribute (`"PHP"`) and its own custom element (`"PHPCodeStyleSettings"`).
- **Field addresses:** each entry names its fields as address strings that the Core resolves:
  - `common:NAME`
  - `indent:NAME`
  - `custom:NAME`
  - `tag:<Element>:NAME` (another plugin's custom element)
  - `lang:<Language>:common:NAME` and `lang:<Language>:indent:NAME` (another language's block)
  - `root:NAME`
  - `other_indent:NAME`
- **Value conversion:** the Core converts by Option type. `true`/`false` becomes a boolean, a number an integer, and comma-separated text a list. A choice uses the entry's `values` map from PhpStorm's int or enum name to a choice id. Joins of several fields use `from(fields)` (ADR-0007).
- **Defaults:** an absent field, or the inherit value `-1`, leaves the Option at its default, which already inherits `general` (ADR-0003).
- **`general`:** the Core owns the mapping of `general` (`root:` and `other_indent:`).
- **No PhpStorm legacy migrations:** an old or renamed field counts as unknown, and `version` attributes are ignored. `codestyle.testing` translates the Research Corpus's `scheme_xml_location` into these addresses.
- **Languages with no installed plugin:** their fields are skipped, including those of the languages left out of v1 (ADR-0009). To get them, the user installs the plugin and imports again. The values of such a language that are already stored stay as they are (ADR-0001), and the report says that they were not updated.
- **Arrangement:** the Core passes each language's parsed `<arrangement>` element to that plugin's `arrangement` module. Its result belongs to the Arrangement design. A language whose XML has no `<arrangement>` gets the default Arrangement.
- **The report:** one `vim.notify` line gives the totals. `R` in the Menu opens the full report in a scratch buffer. For each language, it lists:
  - the imported values;
  - the fields of Options that v1 leaves out;
  - unknown fields;
  - invalid values, with the default used in their place;
  - whether the plugin is not installed.
