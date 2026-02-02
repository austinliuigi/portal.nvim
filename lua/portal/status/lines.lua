local M = {}

--- Get the raw text of a line
--
---@param line portal.StatusLine
---@return string
local function get_raw_line(line)
  local line_str = ""
  for _, chunk in ipairs(line) do
    line_str = line_str .. chunk[1]
  end
  return line_str
end

--- Get the raw text of lines
--
---@param lines portal.StatusLine[]
---@return string[]
function M.get_raw_lines(lines)
  local raw_lines = {}
  for _, line in ipairs(lines) do
    table.insert(raw_lines, get_raw_line(line))
  end
  return raw_lines
end

--- Get the width and height of a block of text
--
---@param lines portal.StatusLine[]
function M.get_dims(lines)
  local width = 0
  local height = #lines
  for _, line in ipairs(lines) do
    local line_str = get_raw_line(line)
    width = math.max(width, #line_str)
  end
  return width, height
end

--- Sort lines in place
--
---@param lines portal.StatusLine[]
function M.sort(lines)
  table.sort(lines, function(l1, l2)
    return get_raw_line(l1) < get_raw_line(l2)
  end)
end

return M
