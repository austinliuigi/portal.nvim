local M = {}

--==============================================================================
-- HELPER FUNCTIONS
--==============================================================================

--- Get the path for the rendered output file of a given portal
--
---@param src string
---@param dest string
---@param bufnr integer
---@return string outfile Absolute path to the output file
M.get_outfile = function(src, dest, bufnr)
  return string.format(
    "%s/%s.%s",
    M.outdir,
    string.format("%s_%s_%s", require("portal.utils").get_escaped_bufname(bufnr), src, dest),
    dest
  )
end

---@param src string
---@param dest string
---@param bufnr? integer
local function get_augroup_id(src, dest, bufnr)
  return vim.api.nvim_create_augroup(string.format("portal-%s-%s-%s", src, dest, bufnr), { clear = false })
end

--==============================================================================
-- API
--==============================================================================

--------------------------------------------------------------------------------
-- VARIABLES
--------------------------------------------------------------------------------

--- Directory containing all the rendered output files
--
M.outdir = vim.fn.stdpath("cache") .. "/portal"
vim.fn.mkdir(M.outdir, "p")

--- Directory to use for temporary files
--
local nvim_tempdir = vim.fs.dirname(vim.fn.tempname())
M.tempdir = nvim_tempdir .. "/portal"
vim.fn.mkdir(M.tempdir, "p")

--------------------------------------------------------------------------------
-- FUNCTIONS
--------------------------------------------------------------------------------

--- Setup custom portal configurations
--
---@param cfg portal.Config
function M.setup(cfg)
  vim.tbl_deep_extend("force", require("portal.config").config, cfg or {})
end

--- Check if a portal is open
--
---@param src string
---@param dest string
---@param bufnr? integer
---@return boolean
function M.is_open(src, dest, bufnr)
  if bufnr == nil then
    return require("portal.utils").tbl_get(require("portal.classes.GlobalViewer").instances, { src, dest }) ~= nil
  end
  return require("portal.utils").tbl_get(require("portal.classes.LocalViewer").instances, { src, dest, bufnr }) ~= nil
end

--- List open portals
--
function M.list()
  print("Global Portals:")
  for src, dest_tbl in pairs(require("portal.classes.GlobalViewer").instances) do
    for dest, _ in pairs(dest_tbl) do
      print(string.format("    - %s --> %s", src, dest))
    end
  end

  print("Local Portals:")
  for src, dest_tbl in pairs(require("portal.classes.LocalViewer").instances) do
    for dest, bufnr_tbl in pairs(dest_tbl) do
      for bufnr, _ in pairs(bufnr_tbl) do
        print(
          string.format(
            "    - %s --> %s (%s)",
            src,
            dest,
            string.gsub(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p"), vim.env.HOME, "~")
          )
        )
      end
    end
  end
end

--- Open a portal and a respective view to it. If type is "global", bufnr has no effect.
--
---@param src? string
---@param dest string
---@param bufnr? integer
function M.open(src, dest, bufnr)
  src = src or vim.o.filetype
  require("portal.utils")

  -- an explicitly provided destination is required
  if dest == nil then
    vim.notify("Portal destination must be provided", vim.log.levels.ERROR, { title = "portal.nvim" })
    return
  end

  -- no config for portal; exit
  local cfg = require("portal.config").get_portal_config(src, dest)
  if cfg == nil then
    vim.notify(
      string.format("No configuration for portal from %s to %s", src, dest),
      vim.log.levels.ERROR,
      { title = "portal.nvim" }
    )
    return
  end

  -- early exit if portal already exists
  if M.is_open(src, dest, bufnr) then
    vim.notify(
      string.format("Portal from %s to %s already exists", src, dest),
      vim.log.levels.INFO,
      { title = "portal.nvim" }
    )
    return
  end

  -- create portal autocommands
  if bufnr then
    vim.api.nvim_create_autocmd({ "BufDelete" }, {
      group = get_augroup_id(src, dest, bufnr),
      buffer = bufnr,
      callback = function()
        M.close(src, dest, bufnr)
      end,
      once = true,
    })
  end
  vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
    group = get_augroup_id(src, dest, bufnr),
    callback = function()
      M.close(src, dest, bufnr)
    end,
    once = true,
  })

  -- instantiate viewer
  if bufnr then
    require("portal.classes.LocalViewer"):construct(src, dest, bufnr)
  else
    require("portal.classes.GlobalViewer"):construct(src, dest)
  end

  vim.notify(
    string.format("Portal from %s to %s successfully opened", src, dest),
    vim.log.levels.INFO,
    { title = "portal.nvim" }
  )
end

--- Close a portal and its view
--
---@param src? string
---@param dest string
---@param bufnr? integer
function M.close(src, dest, bufnr)
  src = src or vim.o.filetype

  if dest == nil then
    vim.notify("Portal destination must be provided", vim.log.levels.ERROR, { title = "portal.nvim" })
    return
  end

  if not M.is_open(src, dest, bufnr) then
    -- vim.notify("Portal from %s to %s is not open", vim.log.levels.INFO, { title = "portal.nvim" })
    return
  end

  vim.api.nvim_del_augroup_by_id(get_augroup_id(src, dest, bufnr))

  -- destroy viewer
  if bufnr then
    require("portal.classes.LocalViewer").instances[src][dest][bufnr]:destruct()
  else
    require("portal.classes.GlobalViewer").instances[src][dest]:destruct()
  end

  vim.notify(
    string.format("Portal from %s to %s successfully closed", src, dest),
    vim.log.levels.INFO,
    { title = "portal.nvim" }
  )
end

return M
