local utils = {}

--- Evaluate if argument is a function, otherwise just return what was passed in
--
---@param arg any
function utils.eval_if_func(arg)
  if type(arg) == "function" then
    return arg()
  end
  return arg
end

--- Throttles a function
--
---@param fn function function to throttle
---@param ms number timeout in ms
---@return function throttled_fn throttled function
---@return timer throttle_timer throttle timer
-- Note: timer:close() at the end or you will leak memory!
function utils.throttle(fn, ms)
  local throttle_timer = vim.uv.new_timer()
  local running = false

  local function throttled_fn(...)
    local args = { ... }
    if not running then
      throttle_timer:start(ms, 0, function()
        running = false
      end)
      running = true
      vim.schedule_wrap(fn)(unpack(args))
    end
  end

  return throttled_fn, throttle_timer
end

--- Create a table that defaults to an empty table instead of nil for indexes within depth
function utils.default_table(tbl)
  return setmetatable(tbl or {}, {
    __index = function(table, key)
      local new_table = utils.default_table()
      table[key] = new_table
      return new_table
    end,
  })
end

return utils
