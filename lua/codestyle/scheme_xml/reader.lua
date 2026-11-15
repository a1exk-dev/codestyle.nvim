-- The strict XML reader of the Scheme XML import (ADR-0010). It reads the
-- part of XML 1.0 that PhpStorm writes: elements, attributes in either quote
-- style, self-closing tags, text, comments, processing instructions such as
-- `<?xml?>`, CDATA, the five named entities and numeric references. It
-- rejects DOCTYPE, and any malformed input gives one error with its line.

--- An element of the tree.
---@class codestyle.XmlElement
---@field name string
---@field attrs table<string, string>
---@field children codestyle.XmlElement[] the child elements, in order
---@field text string the element's own text, comments left out and CDATA kept
---@field line integer where the start tag is, 1-based

--- Why a text is not XML that the reader accepts.
---@class codestyle.XmlError
---@field line integer 1-based
---@field message string

local M = {}

local ENTITIES = { lt = '<', gt = '>', amp = '&', quot = '"', apos = "'" }

local NAME = '^[%a_:][%w_:%.%-]*'

--- The root element of an XML text, or nil and the error.
---@param text string
---@return codestyle.XmlElement?
---@return codestyle.XmlError?
function M.parse(text)
  local pos = 1
  ---@type codestyle.XmlElement[]
  local stack = {}
  ---@type codestyle.XmlElement?
  local root

  -- The line of the last position asked for: the reader mostly moves forward.
  local counted_pos, counted_line = 1, 1

  ---@param at integer
  ---@return integer
  local function line_at(at)
    if at < counted_pos then
      counted_pos, counted_line = 1, 1
    end
    local _, breaks = text:sub(counted_pos, at - 1):gsub('\n', '')
    counted_pos, counted_line = at, counted_line + breaks
    return counted_line
  end

  local function fail(message, at)
    error({ line = line_at(at or pos), message = message }, 0)
  end

  --- Replaces the entities and references of a text.
  ---@param raw string
  ---@param at integer where `raw` starts, for the line of an error
  ---@return string
  local function decode(raw, at)
    return (
      raw:gsub('()&([^;&]*)(;?)', function(offset, body, semicolon)
        local where = at + offset - 1
        if semicolon == '' then
          fail('"&" starts no entity or reference', where)
        end
        if ENTITIES[body] then
          return ENTITIES[body]
        end
        local code = body:match('^#x(%x+)$')
        code = code and tonumber(code, 16) or tonumber(body:match('^#(%d+)$') or '')
        if not code then
          fail(('unknown entity "&%s;"'):format(body), where)
        end
        local ok, char = pcall(vim.fn.nr2char, code, 1)
        if not ok or code == 0 or code > 0x10FFFF then
          fail(('"&%s;" is not a character'):format(body), where)
        end
        return char
      end)
    )
  end

  ---@param raw string
  ---@param at integer
  local function add_text(raw, at)
    if #stack == 0 then
      if raw:match('%S') then
        fail('text outside the root element', at + (raw:find('%S') or 1) - 1)
      end
      return
    end
    local current = stack[#stack]
    current.text = current.text .. decode(raw, at)
  end

  local function start_tag()
    local at = pos
    local name = text:match(NAME, pos + 1)
    if not name then
      fail('expected an element name after "<"')
    end
    if #stack == 0 and root then
      fail('a second root element')
    end
    local parent = stack[#stack]
    ---@type codestyle.XmlElement
    local element = { name = name, attrs = {}, children = {}, text = '', line = line_at(at) }
    pos = pos + 1 + #name
    while true do
      local space, after = text:match('^(%s*)()', pos)
      pos = after
      if text:sub(pos, pos + 1) == '/>' then
        pos = pos + 2
        break
      elseif text:sub(pos, pos) == '>' then
        pos = pos + 1
        table.insert(stack, element)
        break
      end
      if text:sub(pos, pos) == '' then
        fail(('the tag <%s> is not closed'):format(name), at)
      end
      local attr = text:match(NAME, pos)
      if not attr or space == '' then
        fail(('expected an attribute, "/>" or ">" in <%s>'):format(name))
      end
      pos = pos + #attr
      local quote, value_start = text:match('^%s*=%s*(["\'])()', pos)
      if not quote then
        fail(('the attribute %s has no quoted value'):format(attr))
      end
      local value_end = text:find(quote, value_start, true)
      if not value_end then
        fail(('the value of the attribute %s is not closed'):format(attr), value_start)
      end
      local raw = text:sub(value_start, value_end - 1)
      if raw:find('<', 1, true) then
        fail(('"<" in the value of the attribute %s'):format(attr), value_start)
      end
      if element.attrs[attr] then
        fail(('the attribute %s is repeated'):format(attr))
      end
      element.attrs[attr] = decode(raw, value_start)
      pos = value_end + 1
    end
    if parent then
      table.insert(parent.children, element)
    else
      root = element
    end
  end

  local function end_tag()
    local at = pos
    local name, after = text:match('^</([%a_:][%w_:%.%-]*)%s*>()', pos)
    if not name then
      fail('a malformed end tag')
    end
    local open = stack[#stack]
    if not open then
      fail(('the end tag </%s> has no start tag'):format(name), at)
    end
    if open.name ~= name then
      fail(('the end tag </%s> does not match <%s> on line %d'):format(name, open.name, open.line), at)
    end
    table.remove(stack)
    pos = after
  end

  ---@param opening string
  ---@param closing string
  ---@param what string
  ---@return integer start of the body
  ---@return integer stop of the body
  local function skip(opening, closing, what)
    local stop = text:find(closing, pos + #opening, true)
    if not stop then
      fail(what .. ' is not closed')
    end
    local body = pos + #opening
    pos = stop + #closing
    return body, stop - 1
  end

  local ok, problem = pcall(function()
    if text:sub(1, 3) == '\239\187\191' then
      pos = 4
    end
    while pos <= #text do
      local next_tag = text:find('<', pos, true)
      add_text(text:sub(pos, (next_tag or #text + 1) - 1), pos)
      if not next_tag then
        break
      end
      pos = next_tag
      if text:sub(pos, pos + 3) == '<!--' then
        skip('<!--', '-->', 'a comment')
      elseif text:sub(pos, pos + 8) == '<![CDATA[' then
        if #stack == 0 then
          fail('CDATA outside the root element')
        end
        local body, stop = skip('<![CDATA[', ']]>', 'a CDATA section')
        stack[#stack].text = stack[#stack].text .. text:sub(body, stop)
      elseif text:sub(pos, pos + 8) == '<!DOCTYPE' then
        fail('DOCTYPE is not allowed')
      elseif text:sub(pos, pos + 1) == '<?' then
        skip('<?', '?>', 'a processing instruction')
      elseif text:sub(pos, pos + 1) == '</' then
        end_tag()
      elseif text:sub(pos, pos + 1) == '<!' then
        fail('an unknown declaration')
      else
        start_tag()
      end
    end
    if #stack > 0 then
      fail(('the element <%s> is not closed'):format(stack[#stack].name), #text + 1)
    end
    if not root then
      fail('no root element')
    end
  end)
  if not ok then
    if type(problem) ~= 'table' then
      error(problem, 0)
    end
    return nil, problem
  end
  return root
end

return M
