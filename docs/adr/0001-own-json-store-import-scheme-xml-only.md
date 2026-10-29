# Own JSON store; import only PhpStorm Scheme XML

A Code Style lives only in our own JSON files: the Global Code Style in `stdpath('config')/codestyle.json` and the Project Code Style in `<repo root>/.codestyle.json`. Each file holds a format `version` and only the values that differ from the Language Plugin defaults. PhpStorm formats are import sources only. We import Scheme XML, because it is lossless (SQL, Arrangement, "Default" vs explicit values, wrap value 5) and is the format the Behaviour Records were made with. We do not read or write `.editorconfig`: it cannot hold a full Code Style, it means different things for different file paths, and Neovim's built-in reader cannot parse its `ij_*` keys (see the findings of "How complex is PhpStorm-compatible .editorconfig read/write?", #4).

## Considered Options

- **`.editorconfig` as a live store (read+write).** About 1500–2500 LOC, two stores to keep in sync, and PhpStorm's Export still overwrites hand edits.
- **`.editorconfig` import or per-buffer overlay.** About twice the work of Scheme XML import, and it loses data. Ruled out of v1. It may return as its own effort.
- **Lua files.** Loading a project Lua file runs repository code, and the Menu cannot write it back while keeping the user's comments.

## Consequences

- A project Code Style replaces the Global Code Style completely. An Option it does not set falls back to PhpStorm's default, so every teammate formats the same way.
- Saving keeps unknown languages and keys untouched, so a teammate without some Language Plugin does not erase other people's values.
