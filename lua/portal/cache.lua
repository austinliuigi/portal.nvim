local M = {}

-- NOTE: must be a string that can't be in the hash, src, or dest
local cachefile_delimiter = "."

--- Hash and encode a string to a filename-safe string
--
---@param str string
local function hash_to_filename(str)
  local hash_hex = vim.fn.sha256(str)

  ---@diagnostic disable-next-line: param-type-mismatch
  local hash_base64 = vim.base64.encode(vim.text.hexdecode(hash_hex))

  return hash_base64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

--- Directory containing all the cached rendered output files
--
M.cache_outdir = require("portal").outdir .. "/cache"
vim.fn.mkdir(M.cache_outdir, "p")

--- Get the path for the cache file of a given portal
--
---@param src string
---@param dest string
---@param bufnr integer
---@return string cache_outfile Absolute path to the cache file
M.get_cache_outfile = function(src, dest, bufnr)
  return string.format(
    "%s/%s%s%s%s%s",
    M.cache_outdir,
    hash_to_filename(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")),
    cachefile_delimiter,
    src,
    cachefile_delimiter,
    dest
  )
end

--- Split a cache file's name into its constituent parts
--
---@param file string Path or basename of cache file to split
---@return { hash: string, src: string, dest: string }
M.split_cache_file = function(file)
  local split = vim.split(vim.fs.basename(file), cachefile_delimiter, { plain = true })

  assert(#split == 3)

  return {
    hash = split[1],
    src = split[2],
    dest = split[3],
  }
end

M.clean = function()
  local filepaths = require("portal.utils").readdir_filter(M.cache_outdir, function(_)
    return true
  end)

  local curr_time_sec = os.time()
  for _, filepath in ipairs(filepaths) do
    local stat = vim.uv.fs_stat(filepath)
    ---@diagnostic disable-next-line: need-check-nil
    local mtime_sec = stat.mtime.sec

    if (curr_time_sec - mtime_sec) > (require("portal.config").config.cache_retention_days * 60 * 60 * 24) then
      vim.uv.fs_unlink(filepath)
    end
  end
end

--- Remove the oldest cache files for a portal if there are more than a given limit
--
---@param limit integer Size to limit cache to. Must be >= 0.
---@param src string
---@param dest string
---@param bufnr integer
M.limit_cache_to_n_files = function(limit, src, dest, bufnr)
  -- only handle files with a matching source file, portal src, and portal dest
  local filepaths = require("portal.utils").readdir_filter(M.cache_outdir, function(file)
    local parts = M.split_cache_file(file.name)
    return parts.source_file == require("portal.utils").get_escaped_bufname(bufnr)
      and parts.src == src
      and parts.dest == dest
  end)

  if #filepaths <= limit then
    return
  end

  -- sort files in order of ascending modification time
  local mtimes = {}
  local mtimes_to_filepaths = {}
  for _, filepath in ipairs(filepaths) do
    local stat = vim.uv.fs_stat(filepath)

    ---@diagnostic disable-next-line: need-check-nil
    local mtime = stat.mtime.sec .. "-" .. stat.mtime.nsec
    table.insert(mtimes, mtime)
    mtimes_to_filepaths[mtime] = filepath
  end
  table.sort(mtimes)

  -- vim.print(mtimes_to_filepaths)

  -- remove oldest entries
  local n_entries_to_delete = #filepaths - limit
  local n_deleted = 0
  for _, mtime in ipairs(mtimes) do
    if n_deleted >= n_entries_to_delete then
      break
    end

    -- print("removing " .. mtimes_to_filepaths[mtime])
    vim.uv.fs_unlink(mtimes_to_filepaths[mtime])
    n_deleted = n_deleted + 1
  end
end

--- Clean cache on exit
--
vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
  callback = function()
    M.clean()
  end,
  once = true,
})

return M
