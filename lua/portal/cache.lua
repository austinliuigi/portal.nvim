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
---@param unique_str? string String that is used to further uniquely identify the cache entry
---@return string cache_outfile Absolute path to the cache file
M.get_cache_outfile = function(src, dest, bufnr, unique_str)
  unique_str = unique_str or "default"
  return string.format(
    "%s/%s%s%s%s%s%s%s",
    M.cache_outdir,
    hash_to_filename(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")),
    cachefile_delimiter,
    hash_to_filename(unique_str),
    cachefile_delimiter,
    src,
    cachefile_delimiter,
    dest
  )
end

--- Remove cache files older than a configured number of retention days
--
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

--- Clean cache on exit
--
vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
  callback = function()
    M.clean()
  end,
  once = true,
})

return M
