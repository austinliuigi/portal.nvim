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

--- Make directory if it doesn't already exist
--
---@param path string
---@return string path
function utils.ensure_dir_exists(path)
  if vim.fn.exists(path) == "" then
    vim.uv.fs_mkdir(path, 448) -- (448)_10 == (700)_8
  end
  return path
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
--
---@param tbl table|nil initial table
function utils.defaultdict(tbl)
  return setmetatable(tbl or {}, {
    __index = function(table, key)
      local new_table = utils.defaultdict()
      table[key] = new_table
      return new_table
    end,
  })
end

--- Check if a nested table contains the given key
--- e.g. contains({ a = { b = { c = "1", d = "2" } } }, "a", "b", "d") => true
--
---@param tbl table
---@param keys (string|integer)[] Keys to check for, in order of indexing
---@returm boolean
function utils.tbl_contains(tbl, keys)
  for n, key in ipairs(keys) do
    -- ensure any intermediate keys are tables
    if n ~= #keys and type(tbl[key]) ~= "table" then
      return false
    end

    tbl = tbl[key]
  end
  return tbl ~= nil
end

--- Get the value of a key in a nested table. If any intermediate tables don't exist, returns nil.
--
---@param tbl table
---@param keys (string|integer)[] Keys to check for, in order of indexing
---@return any
function utils.tbl_get(tbl, keys)
  local val = tbl
  for n, key in ipairs(keys) do
    -- ensure any intermediate values are tables
    if n ~= #keys and type(val[key]) ~= "table" then
      return nil
    end

    val = val[key]
  end
  return val
end

--- Set the value for a nested table's key. Intermediate tables need not exist.
--- Any intermediate values that are not tables will be overwritten.
--
---@param tbl table
---@param keys (string|integer)[] Keys in order of nesting
---@param val any
---@return table deepest_tbl Table that had val set for keys[#keys]
function utils.tbl_set(tbl, keys, val)
  for n, key in ipairs(keys) do
    -- set the value for the last key
    if n == #keys then
      tbl[key] = val
      break
    end

    if type(tbl[key]) ~= "table" then
      tbl[key] = {}
    end
    tbl = tbl[key]
  end
  return val
end

--- Recursively remove empty tables values in a base table
--
---@param tbl table
function utils.tbl_prune(tbl)
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      utils.tbl_prune(v)
      if vim.tbl_count(v) == 0 then
        tbl[k] = nil
      end
    end
  end
end

return utils
