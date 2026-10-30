-- PROTOTYPE (throwaway): a TOY formatter so that the Preview visibly reacts.
-- It is NOT the engine of ADR-0002. It knows only the Options in `modelled`, with regexes.
local M = {}

local indent_keys = { "use_tab_character", "tab_width", "indent_size", "continuation_indent_size", "keep_indents_on_empty_lines" }
local space_keys = {
  "space_before_method_parentheses", "space_before_method_call_parentheses", "space_before_if_parentheses",
  "space_before_for_parentheses", "space_before_while_parentheses", "space_before_switch_parentheses",
  "space_before_catch_parentheses",
}
local c_like = vim.list_extend(vim.list_extend(vim.list_extend({}, indent_keys), space_keys),
  { "class_brace_style", "method_brace_style", "keep_blank_lines_in_code" })

M.modelled = {
  php = vim.list_extend(vim.deepcopy(c_like), { "lower_case_boolean_const", "lower_case_null_const", "else_if_style" }),
  typescript = vim.list_extend(vim.deepcopy(c_like),
    { "use_double_quotes", "force_quote_style", "use_semicolon_after_statement", "force_semicolon_style" }),
  json = vim.deepcopy(indent_keys),
  shell = { "use_tab_character", "tab_width", "indent_size", "switch_cases_indented", "redirect_followed_by_space" },
}

function M.is_modelled(lang_id, key)
  return vim.tbl_contains(M.modelled[lang_id] or {}, key)
end

local function strip_strings(s)
  s = s:gsub('"[^"]*"', '""')
  s = s:gsub("'[^']*'", "''")
  return s
end

local function make_indent(w, get)
  if get("use_tab_character") then
    local tw = get("tab_width") or 4
    return string.rep("\t", math.floor(w / tw)) .. string.rep(" ", w % tw)
  end
  return string.rep(" ", w)
end

local KW = {}
for _, w in ipairs({ "function", "fn", "return", "array", "match", "list", "isset", "echo", "new", "typeof", "declare", "unset", "empty" }) do
  KW[w] = true
end
local BEFORE = {
  ["if"] = "space_before_if_parentheses", ["elseif"] = "space_before_if_parentheses",
  ["for"] = "space_before_for_parentheses", ["foreach"] = "space_before_for_parentheses",
  ["while"] = "space_before_while_parentheses", ["switch"] = "space_before_switch_parentheses",
  ["catch"] = "space_before_catch_parentheses",
}

local function spaces(line, get)
  if line:match("^%s*[%*/#]") then
    return line
  end
  local out, i = {}, 1
  while true do
    local s, e, word, sp = line:find("([%a_][%w_]*)(%s*)%(", i)
    if not s then
      break
    end
    local prev = s > 1 and line:sub(s - 1, s - 1) or ""
    out[#out + 1] = line:sub(i, s - 1) .. word
    if prev:match("[%w_%$]") then
      out[#out + 1] = sp .. "("
    else
      local key = BEFORE[word]
      if not key and not KW[word] then
        key = line:sub(1, s - 1):match("function%s+&?$") and "space_before_method_parentheses"
          or "space_before_method_call_parentheses"
      end
      local v = key and get(key)
      out[#out + 1] = (v == nil and sp or (v and " " or "")) .. "("
    end
    i = e + 1
  end
  out[#out + 1] = line:sub(i)
  return table.concat(out)
end

local function brace_key(line)
  if line:match("^%s*[%w%s]*class%s") or line:match("^%s*interface%s") or line:match("^%s*trait%s") then
    return "class_brace_style"
  end
  if line:match("function%s+[%w_]+%s*%b()") then
    return "method_brace_style"
  end
end

local function braces(lines, get)
  local out = {}
  for _, line in ipairs(lines) do
    local k = line:match("{%s*$") and brace_key(line)
    local style = k and get(k)
    if style and style ~= "end_of_line" and style ~= "next_line_if_wrapped" then
      out[#out + 1] = (line:gsub("%s*{%s*$", ""))
      out[#out + 1] = "{"
    elseif line:match("^%s*{%s*$") and #out > 0 and brace_key(out[#out])
      and (get(brace_key(out[#out])) == "end_of_line" or get(brace_key(out[#out])) == "next_line_if_wrapped") then
      out[#out] = out[#out] .. " {"
    else
      out[#out + 1] = line
    end
  end
  return out
end

local function blank(lines, get)
  local max = get("keep_blank_lines_in_code")
  if not max then
    return lines
  end
  local out, run = {}, 0
  for _, l in ipairs(lines) do
    if l:match("^%s*$") then
      run = run + 1
      if run <= max then
        out[#out + 1] = ""
      end
    else
      run = 0
      out[#out + 1] = l
    end
  end
  return out
end

local function reindent_c(lines, get)
  local size, cont = get("indent_size") or 4, get("continuation_indent_size") or 8
  local depth, prev = 0, nil
  local out = {}
  for _, line in ipairs(lines) do
    local t = line:gsub("^%s+", "")
    if t == "" then
      out[#out + 1] = get("keep_indents_on_empty_lines") and make_indent(depth * size, get) or ""
    else
      local s = strip_strings(t)
      local closers = #(s:match("^[%)%]}]+") or "")
      local w = math.max(0, depth - closers) * size
      if t:match("^%*") then
        w = w + 1
      elseif prev and (prev:match("[=%+%-%*/%.|&%?:]%s*$") or prev:match("%f[%w]return%s*$")) and closers == 0 then
        w = w + cont
      end
      out[#out + 1] = make_indent(w, get) .. t
      local code = s:gsub("//.*$", "")
      for _ in code:gmatch("[%(%[{]") do
        depth = depth + 1
      end
      for _ in code:gmatch("[%)%]}]") do
        depth = math.max(0, depth - 1)
      end
      if not t:match("^[/%*#]") then
        prev = code
      end
    end
  end
  return out
end

local function reindent_shell(lines, get)
  local size, case_in = get("indent_size") or 2, get("switch_cases_indented")
  local depth, in_item = 0, false
  local out = {}
  for _, line in ipairs(lines) do
    local t = line:gsub("^%s+", "")
    local d = depth
    local reopen = t:match("^else%f[%W]") or t:match("^elif%f[%W]")
    if t:match("^fi%f[%W]") or t:match("^done%f[%W]") or t:match("^}") then
      depth = depth - 1
      d = depth
    elseif reopen then
      d = depth - 1
    elseif t:match("^esac") then
      if in_item then
        depth, in_item = depth - 1, false
      end
      depth = depth - (case_in and 1 or 0)
      d = depth
    end
    if get("redirect_followed_by_space") ~= nil then
      t = t:gsub("([^%s<>&%d]?%d?)(>>?)%s*([%w%$/\"])", function(a, op, b)
        return a .. op .. (get("redirect_followed_by_space") and " " or "") .. b
      end)
    end
    out[#out + 1] = t == "" and "" or make_indent(math.max(0, d) * size, get) .. t
    if reopen then
      -- else/elif close and reopen the same level
    elseif t:match("then$") or t:match("do$") or t:match("{$") then
      depth = depth + 1
    elseif t:match("^case%s.*%sin$") then
      depth = depth + (case_in and 1 or 0)
    elseif t:match("^[^%(]*%)") and not t:match(";;") and not in_item and depth >= 0 and t:match("^[%w%*%-|\"']+%)") then
      depth, in_item = depth + 1, true
    end
    if t:match(";;%s*$") and in_item then
      depth, in_item = depth - 1, false
    end
  end
  return out
end

local function php_conversion(lines, get)
  local function conv(l, words, mode)
    if mode ~= "lower" and mode ~= "upper" then
      return l
    end
    return (l:gsub("%f[%w_%$]([%a_]+)%f[^%w_]", function(w)
      if words[w:lower()] then
        return mode == "upper" and w:upper() or w:lower()
      end
    end))
  end
  local style = get("else_if_style")
  for i, l in ipairs(lines) do
    l = conv(l, { ["true"] = true, ["false"] = true }, get("lower_case_boolean_const"))
    l = conv(l, { ["null"] = true }, get("lower_case_null_const"))
    if style == "separate" then
      l = l:gsub("%f[%w]elseif%f[%W]", "else if")
    elseif style == "combine" then
      l = l:gsub("%f[%w]else%s+if%f[%W]", "elseif")
    end
    lines[i] = l
  end
  return lines
end

local function ts_punctuation(lines, get)
  for i, l in ipairs(lines) do
    if get("force_quote_style") == "always" then
      if get("use_double_quotes") == "single" then
        l = l:gsub('"([^"\']*)"', "'%1'")
      else
        l = l:gsub("'([^'\"]*)'", '"%1"')
      end
    end
    if get("force_semicolon_style") == "always" and get("use_semicolon_after_statement") == "dont_use"
      and not l:match("^%s*for%s*%(") then
      l = l:gsub(";%s*$", "")
    end
    lines[i] = l
  end
  return lines
end

function M.format(lang_id, sample, get)
  local lines = vim.split((sample:gsub("\r", "")), "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  if lang_id == "shell" then
    return reindent_shell(lines, get)
  end
  if lang_id == "php" then
    lines = php_conversion(lines, get)
  elseif lang_id == "typescript" then
    lines = ts_punctuation(lines, get)
  end
  if lang_id ~= "json" then
    for i, l in ipairs(lines) do
      lines[i] = spaces(l, get)
    end
    lines = braces(lines, get)
    lines = blank(lines, get)
  end
  return reindent_c(lines, get)
end

return M
