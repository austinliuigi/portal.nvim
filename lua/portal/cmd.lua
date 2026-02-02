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

return M
