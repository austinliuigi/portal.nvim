local M = {}

--- Evaluate if argument is a function, otherwise just return what was passed in
--
---@param arg any
---@return any
function M.eval_if_func(arg)
  if type(arg) == "function" then
    return arg()
  end
  return arg
end

--- Get the absolute path of a buffer, escaped to be filename-safe
--
---@param bufnr integer
function M.get_escaped_bufname(bufnr)
  return vim.api.nvim_buf_get_name(bufnr):gsub("/", "%%")
end

--- Make directory if it doesn't already exist
--
---@param path string
---@return string path
function M.ensure_dir_exists(path)
  if vim.fn.exists(path) == "" then
    vim.uv.fs_mkdir(path, 448) -- (448)_10 == (700)_8
  end
  return path
end

--- Get a list of files in a directory, filtered through a predicate
--
---@param dir string
---@param predicate function({name: string, type: string}): boolean
---@return string[] matched_filepaths
function M.readdir_filter(dir, predicate)
  ---@diagnostic disable-next-line: param-type-mismatch
  local all_files = vim.uv.fs_readdir(vim.uv.fs_opendir(dir, nil, 9999))
  if all_files == nil then
    return {}
  end

  dir:gsub("/$", "") -- remove trailing slash from dir

  return vim
    .iter(all_files)
    :filter(predicate)
    :map(function(f)
      return dir .. "/" .. f.name
    end)
    :totable()
end

--- Create a table that defaults to a table instead of nil for new indices
--
---@param tbl table|nil initial table
---@return table
function M.defaultdict(tbl)
  return setmetatable(tbl or {}, {
    __index = function(table, key)
      local new_table = M.defaultdict()
      table[key] = new_table
      return new_table
    end,
  })
end

--- Get the value of a key in a nested table. If any intermediate tables don't exist, returns nil.
--
---@param tbl table
---@param keys (string|integer)[] Keys to check for, in order of indexing
---@return any
function M.tbl_get(tbl, keys)
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
function M.tbl_set(tbl, keys, val)
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

--- Remove keys with empty tables values in a base table. Recurse into keys with table values a maximum of depth times.
--- e.g. tbl_prune({ a = { b1 = {}, b2 = { c = {}, }, } }, 1) -> { a = { b2 = { c = {}, }, } }
--
---@param tbl table
---@param depth? integer
function M.tbl_prune(tbl, depth)
  depth = depth or 9999

  for k, v in pairs(tbl) do
    if type(v) == "table" then
      if depth > 0 then
        M.tbl_prune(v, depth - 1)
      end
      if vim.tbl_count(v) == 0 then
        tbl[k] = nil
      end
    end
  end
end

return M
