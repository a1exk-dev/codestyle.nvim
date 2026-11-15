-- The cases of the fake plugin that are expected to fail (ADR-0013): case id → reason.
return {
  ['ij_lua_todo_marker/Default/FIXME/todo.lua'] = 'the fake formatter ignores TODO markers',
  ['preset/Mixed'] = 'the fixture diff differs from the Preset on purpose',
}
