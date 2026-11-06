# `general` holds six Options, and the Core applies markers and the file-wide rules

The Core owns the `general` language (ADR-0003, ADR-0009). It holds only the six General controls that change what Reformat outputs: Hard wrap at, Do not format, and the four formatter marker controls. The Core applies them, and the rules that the Behaviour Records show in every language, in every format run: the Preview, real buffers and `codestyle.testing`. So a Language Plugin writes no code for them, and each family map can take them as given ("Which General Options does the Core own, and how do they act on a format run?", #47).

## The Options

| Key | Type | Default | Tab |
|---|---|---|---|
| `hard_wrap_at` | integer 1–1000 | 120 | General |
| `do_not_format` | list of strings | empty | Formatter |
| `markers.enabled` | boolean | true | Formatter |
| `markers.off` | string | `@formatter:off` | Formatter |
| `markers.on` | string | `@formatter:on` | Formatter |
| `markers.regex` | boolean | false | Formatter |

"General" is an entry in the Menu's language list with PhpStorm's two Tabs. `markers.off`, `markers.on` and `markers.regex` are dimmed while `markers.enabled` is false. Language Options inherit `hard_wrap_at` (ADR-0003). The Scheme XML import maps all six through `root:` addresses (ADR-0010).

## Considered Options

- **Keep more of the General page:** Line separator for new files, Wrap on typing, Detect existing indents, Visual guides and Enable EditorConfig support. Left out, because Reformat never applies them (ADR-0003 scope) or because `.editorconfig` is not read (ADR-0001).
- **Each Language Plugin finds and protects marker regions.** Rejected: sixteen plugins would repeat one odd matcher, and third parties would get it wrong.
- **Java regex syntax for the marker tags**, as PhpStorm stores them. Rejected for Vim syntax, as for Arrangement rules (ADR-0011).
- **"Do not format" folder patterns only in a Project Code Style.** Rejected: patterns are matched from the repo top for the Global Code Style too.
- **Mixed line endings and trailing spaces normalised only in the golden tests.** Rejected: real buffers would differ from PhpStorm on the same file.

## Consequences

- **Marker regions:** before a Language Plugin runs, the Core finds the regions in the whole file text, including embedded parts, and makes them read-only parts, the same mechanism as a part that cannot be formatted (ADR-0007). It copies PhpStorm's rules exactly: a tag is found anywhere, even in a string; in plain mode the first character matches exactly and the rest ignores case; there is no nesting, so the first on-marker closes the region; an off-marker without an on-marker keeps the rest of the file; the off-marker line is formatted. In regex mode the tags are case-sensitive Vim regexes searched in the text. A selection inside a region changes nothing.
- **Plugin quirks are declared, not coded:** a spec flag says that the on-marker line belongs to the region, so it keeps its column (HTML, XML, JSON). Markdown reads `markers.enabled` for its blank lines around `<!-- -->` comments and lists.
- **Regexes:** the Menu refuses a tag that is not a valid Vim regex. The Scheme XML import and the golden-test adapter convert Java patterns (`(?i)` to `\c`, and so on), and the import report lists the ones they cannot convert. A regex that matches nothing does nothing, as in PhpStorm.
- **Arrangement ignores markers**, as PhpStorm's Rearrange does (`ArrangementEngine` never reads formatter tags). A moved entry keeps its text as written, and the formatter then finds the regions in the rearranged text.
- **Do not format:** globs, case-sensitive, matched against the buffer's path from the top of its repo, the root that finds `.codestyle.json` (ADR-0001). Outside a repo, from Neovim's working directory. A pattern with no `/` matches a file name in any folder. A match skips the whole run, Arrangement included, as in PhpStorm (`ArrangementEngine` checks the excluded files). The first skipped run in a buffer gives one notice that names the pattern, and later runs are quiet (ADR-0014). The Preview has no path, so it never skips.
- **Mixed line endings:** a run converts every line to the ending that most lines use, with LF on a tie. In a real buffer the Core removes the `\r`s and sets `fileformat=dos` when CRLF wins. A file with one ending keeps it.
- **Trailing spaces:** after formatting, the Core removes trailing blanks on the lines the run changed, never on untouched lines and never the indent that "Keep indents on empty lines" puts on a blank line. This is PhpStorm's save step that every Behaviour Record includes. No final newline is ever added.
