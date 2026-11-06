-- What the fake `lua` exports to the plugins that use it (ADR-0007).

return {
  build = require('codestyle.languages.lua.formatter').build,
}
