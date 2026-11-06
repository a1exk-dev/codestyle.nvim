---@meta
-- LuaCATS annotations of the Language Plugin contract, `api` 1 (ADR-0007).
-- Plugin repos check their spec and formatter against them with LuaLS
-- (ADR-0013). Within one `api`, fields are only added, and only as optional.

---@alias codestyle.OptionType 'boolean'|'integer'|'choice'|'string'|'list'|'order'

--- One Option of a language (ADR-0003).
---@class codestyle.OptionSpec
---@field key string the stored path, nested by topic with dots, such as `spaces.around_assignment`
---@field type codestyle.OptionType
---@field default any
---@field label string

--- The spec module `lua/codestyle/languages/<id>.lua` of a Language Plugin (ADR-0007).
---@class codestyle.Spec
---@field api integer the contract version, `require('codestyle').api`
---@field id string the language id, the key under `languages` in a Code Style file (ADR-0003)
---@field name string the display name
---@field filetypes string[] the Neovim filetypes that the plugin claims (ADR-0015)
---@field match? fun(buf: integer): boolean claims a buffer whose filetype no spec lists, or that has none; build it with `require('codestyle').match_globs` (ADR-0015)
---@field parsers table<string, string[]> filetype → parser names, first installed wins; `default` is required (ADR-0015)
---@field uses? table<string, integer> language id → the export version this plugin needs from that plugin (ADR-0007)
---@field exports? codestyle.Exports what this plugin offers to plugins that use it (ADR-0007)
---@field options codestyle.OptionSpec[]
--- The key of the boolean Option that is PhpStorm's "Keep indents on empty lines", if the
--- language has one. `:checkhealth codestyle` warns when editorconfig's trim would strip those indents.
---@field keep_indents_on_empty_lines? string
---@field formatter string the module path of the `codestyle.Formatter`, required on first format

--- What a Language Plugin offers to the plugins that `uses` it (ADR-0007).
--- Within one version, only optional fields are added.
---@class codestyle.Exports
---@field version integer

--- The resolved Option values of one language, nested like the stored keys.
---@alias codestyle.Values table<string, any>

--- What the Core passes to a plugin's functions. Plugin functions read only
--- `ctx` and their arguments (ADR-0016).
---@class codestyle.FormatContext
---@field language string the language id
---@field root TSNode the root of the parse tree of `source`
---@field source string the text being formatted, lines joined by `\n`
---@field values codestyle.Values

--- The rules that the engine calls on a parent Block (ADR-0007).
---@class codestyle.Rules
--- The Spacing of the Gap between two adjacent children of `parent`, or nil to keep the Gap.
---@field spacing? fun(parent: codestyle.Block, left: codestyle.Block, right: codestyle.Block, values: codestyle.Values): codestyle.Spacing?

--- The `formatter` module of a Language Plugin (ADR-0007).
---@class codestyle.Formatter
---@field build fun(ctx: codestyle.FormatContext): codestyle.Block
---@field rules codestyle.Rules

--- One text change: replace the text from the start to the end position
--- (rows 0-based, byte columns, end exclusive) with `text`.
---@class codestyle.Edit
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer
---@field text string
