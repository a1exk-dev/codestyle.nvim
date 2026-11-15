# Own JSON store; import only PhpStorm Scheme XML

A Code Style lives only in our own JSON files: the Global Code Style in `stdpath('config')/codestyle.json` and the Project Code Style in `.codestyle.json` at the Project root. Each file holds a format `version` and only the values that differ from the Language Plugin defaults. PhpStorm formats are import sources only. We import Scheme XML, because it is lossless (SQL, Arrangement, "Default" vs explicit values, wrap value 5) and is the format the Behaviour Records were made with. We do not read or write `.editorconfig`: it cannot hold a full Code Style, it means different things for different file paths, and Neovim's built-in reader cannot parse its `ij_*` keys (see the findings of "How complex is PhpStorm-compatible .editorconfig read/write?", #4).

## Considered Options

- **`.editorconfig` as a live store (read+write).** About 1500–2500 LOC, two stores to keep in sync, and PhpStorm's Export still overwrites hand edits.
- **`.editorconfig` import or per-buffer overlay.** About twice the work of Scheme XML import, and it loses data. Ruled out of v1. It may return as its own effort.
- **Lua files.** Loading a project Lua file runs repository code, and the Menu cannot write it back while keeping the user's comments.

## Consequences

- The Project root is Neovim's working directory (`:pwd`) of the current window, read again at each run, so `:cd`, `:tcd` and `:lcd` switch the project, as opening a folder does in PhpStorm. The Project Code Style applies to each buffer whose file is under the Project root. A buffer outside it, and a buffer under it while `.codestyle.json` does not exist, uses the Global Code Style. `.git` plays no part, and a `.codestyle.json` in a subfolder or in a folder above the Project root is ignored. Saving the Project Code Style from the Menu creates the file at the Project root, in a repo or not. The Menu refuses the Project scope for a buffer outside the Project root (a1exk-dev/codestyle-home#36).
- A project Code Style replaces the Global Code Style completely. An Option it does not set falls back to PhpStorm's default, so every teammate formats the same way.
- Saving keeps unknown languages and keys untouched, so a teammate without some Language Plugin does not erase other people's values.
- A broken Code Style file is refused as a whole. A file is broken when it is not valid JSON, when its top level is not an object, when its `version` is missing or is not one that this Core reads, or when its `languages` is not an object. Then no buffer of that scope is formatted, and each run gives one error that names the file and the line. A broken Project Code Style does not fall back to the Global Code Style or to the defaults, because then the next format would silently reformat the code to a style that nobody chose. The Menu does not open that Code Style, saving refuses to write over the file, and "Copy the Global Code Style" copies nothing when the Global file is broken. The user fixes or deletes the file (a1exk-dev/codestyle-home#35).
