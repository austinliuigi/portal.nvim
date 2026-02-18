local M = {}

--- Interpolate a command with predefined substitutions
--
---@param cmd portal.Cmd
---@param substitutions portal.CmdSubstitutions
M.interpolate = function(cmd, substitutions)
  substitutions = substitutions or {}

  local normalized_substitutions = {}
  for key, val in pairs(substitutions) do
    if type(val) == "function" then
      normalized_substitutions[key] = val()
    else
      normalized_substitutions[key] = val
    end
  end

  local interpolated_cmd = {}
  for _, arg in ipairs(require("portal.utils").eval_if_func(cmd)) do
    arg = require("portal.utils").eval_if_func(arg)
    local interpolated_arg = arg:gsub("$%u+", normalized_substitutions)
    table.insert(interpolated_cmd, interpolated_arg)
  end
  return interpolated_cmd
end

--- Wrap a command using `script`, so that ansi colors are sent by the command
--
---@param cmd string[]
---@return string[]
---@return boolean
M.wrap = function(cmd)
  if vim.fn.executable("script") == 0 then
    return cmd, false
  end

  -- wrap each arg in quotes so they are properly separated after being wrapped by script
  -- e.g. { "bash", "-c", "cat file.txt" } -> { "'bash'", "'-c'", "'cat file.txt'" }
  --    script -qec "bash -c cat file.txt" -> script -qec "bash -c 'cat file.txt'"
  local cmd_quoted = vim.deepcopy(cmd)
  for i, arg in ipairs(cmd_quoted) do
    cmd_quoted[i] = '"' .. arg .. '"'
  end
  return { "script", "-qec", table.concat(cmd_quoted, " "), "/dev/null" }, true
end

return M
