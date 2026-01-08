local M = {}
local utils = require("portal.utils")

--- Tracks active portal components
--
---@type portal.ActiveComponents
local active_portal_components = { converters = {}, local_viewers = {}, global_viewers = {} }

--==============================================================================
-- HELPER FUNCTIONS
--==============================================================================

--- Hash and encode a string to a filename-safe string
--
---@param str string
local function hash_to_filename(str)
  local hash_hex = vim.fn.sha256(str)

  ---@diagnostic disable-next-line: param-type-mismatch
  local hash_base64 = vim.base64.encode(vim.text.hexdecode(hash_hex))

  return hash_base64:gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

--- Get the absolute path of a buffer, escaped to be filename-safe
--
---@param bufnr integer
local function get_escaped_bufname(bufnr)
  return vim.api.nvim_buf_get_name(bufnr):gsub("/", "%%")
end

--- Get a list of filtered files in a directory
--
---@param dir string
---@param predicate function({name: string, type: string}): boolean
---@return string[] matched_filepaths
local function readdir_filter(dir, predicate)
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

--- Get the path for the rendered output file of a given portal
--
---@param pd portal.PortalDescription
---@return string outfile Absolute path to the output file
local function get_outfile(pd)
  return string.format(
    "%s/%s.%s",
    M.outdir,
    string.format("%s_%s_%s", get_escaped_bufname(pd.bufnr), pd.src, pd.dest),
    pd.dest
  )
end

--- Get the path for the cache file of a given portal
--
---@param pd portal.PortalDescription
---@return string cache_outfile Absolute path to the cache file
local function get_cache_outfile(pd)
  return string.format(
    "%s/%s.%s.%s.%s",
    M.cache_outdir,
    get_escaped_bufname(pd.bufnr),
    hash_to_filename(table.concat(vim.api.nvim_buf_get_lines(pd.bufnr, 0, -1, false), "\n")),
    pd.src,
    pd.dest
  )
end

--- Split a cache file's name into its constituent parts
--
---@param file string Path or basename of cache file to split
---@return { source_file: string, hash: string, src: string, dest: string }
local function split_cache_file(file)
  local split = vim.split(vim.fs.basename(file), ".", { plain = true })

  assert(#split >= 4)

  -- HACK: source file can include the pattern but the hash, src, and dest can't
  local result = {}
  result.dest = table.remove(split)
  result.src = table.remove(split)
  result.hash = table.remove(split)
  result.source_file = table.concat(split, ".")
  return result
end

--- Remove the oldest cache files for a portal if there are more than a given limit
--
---@param size integer Size to limit cache to. Must be >= 0.
---@param pd portal.PortalDescription
local function limit_cache_to_n_files(size, pd)
  -- only handle files with a matching source file, portal src, and portal dest
  local filepaths = readdir_filter(M.cache_outdir, function(file)
    local parts = split_cache_file(file.name)
    -- TODO: make this work with global portals
    return parts.source_file == get_escaped_bufname(pd.bufnr) and parts.src == pd.src and parts.dest == pd.dest
  end)

  if #filepaths <= size then
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
  local n_entries_to_delete = #filepaths - size
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

--- Get a unique id for a portal
--
---@param pd portal.PortalDescription
local function get_id(pd)
  return string.format("%s_%s_%s_%s", vim.fn.getpid(), pd.bufnr, pd.src, pd.dest)
end

--- Interpolate a command with predefined substitutions
--
---@param cmd portal.Cmd
---@param pd portal.PortalDescription
local function interpolate_cmd(cmd, pd)
  local substitutions = {
    ["$INFILE"] = vim.api.nvim_buf_get_name(pd.bufnr),
    ["$OUTFILE"] = get_outfile(pd),
    ["$ID"] = get_id(pd),
  }

  local interpolated_cmd = {}
  for _, arg in ipairs(utils.eval_if_func(cmd)) do
    local interpolated_arg = arg:gsub("$%u+", substitutions)
    table.insert(interpolated_cmd, interpolated_arg)
  end
  return interpolated_cmd
end

--- Get the viewer for a portal
--
---@param pd portal.PortalDescription
---@return portal.LocalViewer|portal.GlobalViewer?
local function get_viewer(pd)
  if pd.bufnr == nil then
    return utils.tbl_get(active_portal_components.global_viewers, { pd.src, pd.dest })
  end
  return utils.tbl_get(active_portal_components.local_viewers, { pd.bufnr, pd.src, pd.dest })
end

--- Get the viewer for an open portal
--
---@param pd portal.PortalDescription
---@return portal.Converter?
local function get_converter(pd)
  return utils.tbl_get(active_portal_components.converters, { pd.bufnr, pd.src, pd.dest })
end

--- Get the effective description of a portal
--
---@param pd portal.PortalDescription
---@return portal.LocalPortalDescription? converter_pd
local function viewer_pd_to_active_converter_pd(pd)
  -- handle local viewer
  if pd.bufnr ~= nil and get_converter(pd) then
    ---@diagnostic disable-next-line: return-type-mismatch
    return get_converter(pd) and pd or nil
  end

  -- handle global viewer
  local viewer = get_viewer(pd)
  if viewer.bufnr == nil then
    return nil
  else
    local converter_pd = vim.tbl_extend("error", pd, { bufnr = viewer.bufnr })
    return get_converter(converter_pd) and converter_pd or nil
  end
end

--- Get viewers sharing the same single converter
--
---@param pd portal.LocalPortalDescription
---@return portal.LocalViewer|portal.GlobalViewer[]
local function converter_pd_to_active_viewer_pds(pd)
  local viewer_pds = {}

  -- insert local viewer
  if get_viewer(pd) then
    table.insert(viewer_pds, pd)
  end

  -- insert global viewer
  local pd_global = vim.deepcopy(pd)
  pd_global.bufnr = nil
  if get_viewer(pd_global) then
    table.insert(viewer_pds, pd_global)
  end

  return viewer_pds
end

--- Open the viewer for a portal if not already open, otherwise refresh
--
---@param pd portal.PortalDescription
local function view(pd)
  local viewer = get_viewer(pd)
  assert(viewer ~= nil)

  local interpolated_cmd = interpolate_cmd(viewer.cfg.open_cmd, pd)
  -- vim.notify(table.concat(interpolated_cmd, " "))

  if viewer.proc == nil then
    viewer.proc = vim.system(
      interpolated_cmd,
      { text = true, detach = true },
      vim.schedule_wrap(function(obj)
        if obj.code ~= 0 then
          vim.notify(
            string.format("Failed to open viewer, exited with code %s\n[stderr]: %s", obj.code, obj.stderr),
            vim.log.levels.ERROR,
            { title = "portal.nvim" }
          )
        end
        if not viewer.cfg.detach then
          M.close(pd)
        end
      end)
    )
  else
    if pd.bufnr == nil then
      -- TODO: switch
    else
      -- TODO: refresh
    end
  end
end

--- Generate the output file for an open portal
--
---@param pd portal.LocalPortalDescription
local function convert(pd)
  local converter = get_converter(pd)
  assert(converter ~= nil)

  converter.busy = true

  -- handle cache for one-shot converters
  local cache_outfile -- used only for one-shot converters
  if not converter.cfg.daemon then
    cache_outfile = get_cache_outfile(pd)
    local cache_outfile_parts = split_cache_file(cache_outfile)

    -- any cache files with the same hash, source, and dest should have the same contents
    local matching_cache_files = readdir_filter(M.cache_outdir, function(file)
      local file_parts = split_cache_file(file.name)
      return cache_outfile_parts.hash == file_parts.hash
        and cache_outfile_parts.src == file_parts.src
        and cache_outfile_parts.dest == file_parts.dest
    end)

    -- vim.print(matching_cache_files)

    -- cache hit --------------------------------------------------------------
    if #matching_cache_files > 0 then
      if not vim.uv.fs_stat(cache_outfile) then
        vim.uv.fs_link(matching_cache_files[1], cache_outfile)
      end
      vim.uv.fs_copyfile(cache_outfile, get_outfile(pd))
      converter.busy = false

      for _, viewer_pd in ipairs(converter_pd_to_active_viewer_pds(pd)) do
        view(viewer_pd)
      end

      if converter.queued then
        converter.queued = false
        convert(pd)
      end

      return
    end
  end

  -- execute converter process ------------------------------------------------
  converter.proc = vim.system(
    interpolate_cmd(converter.cfg.cmd, pd),
    {
      text = true,
      detach = false,
      ---@diagnostic disable-next-line: assign-type-mismatch
      stdin = converter.cfg.stdin and vim.api.nvim_buf_get_lines(0, 0, -1, false) or false,
    },
    -- callback
    vim.schedule_wrap(function(obj)
      converter.busy = false

      if obj.code ~= 0 then
        vim.notify(
          string.format(
            "Conversion for portal failed (src = %s, dest = %s). Process exited with code %s.\n[stderr]: %s",
            pd.src,
            pd.dest,
            obj.code,
            obj.stderr
          ),
          vim.log.levels.ERROR,
          { title = "portal.nvim" }
        )
      else
        if not converter.cfg.daemon then
          -- cache the output
          vim.uv.fs_copyfile(get_outfile(pd), cache_outfile)
          limit_cache_to_n_files(5, pd) -- TODO: don't hardcode size
        end

        for _, viewer_pd in ipairs(converter_pd_to_active_viewer_pds(pd)) do
          view(viewer_pd)
        end
      end

      if converter.queued then
        converter.queued = false
        convert(pd)
      end
    end)
  )
end

--- Initialize the converter for a portal if it doesn't exist
--
---@param pd portal.LocalPortalDescription
local function make_converter(pd)
  local converter = utils.tbl_set(active_portal_components.converters, { pd.bufnr, pd.src, pd.dest }, {
    busy = false,
    queued = false,
    augroup_id = vim.api.nvim_create_augroup(string.format("portal-converter-%s-%s-%s", pd.bufnr, pd.src, pd.dest), {}),
    cfg = require("portal.config").cfg_from_pd(pd).converter,
  })

  -- reconvert on autocmd events for one-shot (non-daemon) converters
  if not converter.cfg.daemon then
    vim.api.nvim_create_autocmd(converter.cfg.stdin and { "TextChanged", "TextChangedI" } or "BufWritePost", {
      group = converter.augroup_id,
      buffer = pd.bufnr,
      callback = function()
        if converter.busy then
          converter.queued = true
        else
          convert(pd)
        end
      end,
    })
  end
end

--- Remove a converter for a portal
--
---@param pd portal.LocalPortalDescription
local function remove_converter(pd)
  local converter = get_converter(pd)

  -- early exit if portal doesn't have an associated converter
  if converter == nil then
    return
  end

  vim.api.nvim_del_augroup_by_id(converter.augroup_id)

  if converter.proc then -- portals with no converter or have only hit the cache have no converter_proc
    if not converter.proc:is_closing() then
      converter.proc:kill(15)
    end
  end

  active_portal_components.converters[pd.bufnr][pd.src][pd.dest] = nil
  utils.tbl_prune(active_portal_components.converters)
end

--- Switch the buffer to the current buffer for a global portal
--
---@param pd portal.PortalDescription
local function global_portal_switch(pd)
  assert(pd.bufnr == nil)
  assert(pd.src == vim.o.filetype)

  local viewer = get_viewer(pd)
  assert(viewer ~= nil)

  local new_bufnr = vim.api.nvim_get_current_buf()

  -- if new buffer is the same as the current one, early exit
  if viewer.bufnr == new_bufnr then
    return
  end

  -- potentially remove old converter
  if viewer.bufnr ~= nil then
    local old_converter_pd = viewer_pd_to_active_converter_pd(pd)
    ---@diagnostic disable-next-line: param-type-mismatch
    if #converter_pd_to_active_viewer_pds(old_converter_pd) == 0 then
      ---@diagnostic disable-next-line: param-type-mismatch
      remove_converter(old_converter_pd)
    end
  end

  viewer.bufnr = new_bufnr
  view(pd) -- switch to new portal

  local new_converter_pd = viewer_pd_to_active_converter_pd(pd)
  if get_converter(new_converter_pd) == nil then
    make_converter(new_converter_pd)
  end
end

--- Initialize the viewer for a portal if it doesn't exist
--
---@param pd portal.PortalDescription
local function make_viewer(pd)
  local init = {
    augroup_id = vim.api.nvim_create_augroup(string.format("portal-viewer-%s-%s-%s", pd.bufnr, pd.src, pd.dest), {}),
    cfg = require("portal.config").cfg_from_pd(pd).viewer,
  }

  local viewer
  if pd.bufnr == nil then
    viewer = utils.tbl_set(active_portal_components.global_viewers, { pd.src, pd.dest }, init)

    -- switch source when matching buffer is focused
    vim.api.nvim_create_autocmd("FileType", {
      group = viewer.augroup_id,
      pattern = pd.src,
      callback = function()
        global_portal_switch(pd)
      end,
    })

    -- trigger global portal immediately if already in matching source file
    if pd.src == vim.api.nvim_buf_call(1, function()
      return vim.o.filetype
    end) then
      vim.api.nvim_exec_autocmds("FileType", { group = viewer.augroup_id })
    end
  else
    viewer = utils.tbl_set(active_portal_components.local_viewers, { pd.bufnr, pd.src, pd.dest }, init)
  end

  vim.api.nvim_create_autocmd({ "BufDelete" }, {
    group = viewer.augroup_id,
    buffer = pd.bufnr,
    callback = function()
      M.close(pd)
    end,
    once = true,
  })

  vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
    group = viewer.augroup_id,
    callback = function()
      M.close(pd)
    end,
    once = true,
  })
end

--- Remove a viewer for a portal
--
---@param pd portal.PortalDescription
local function remove_viewer(pd)
  local viewer = get_viewer(pd)
  assert(viewer ~= nil)

  vim.api.nvim_del_augroup_by_id(viewer.augroup_id)

  if pd.bufnr == nil then
    active_portal_components.global_viewers[pd.src][pd.dest] = nil
    utils.tbl_prune(active_portal_components.global_viewers)
  else
    active_portal_components.local_viewers[pd.bufnr][pd.src][pd.dest] = nil
    utils.tbl_prune(active_portal_components.local_viewers)
  end

  if viewer.proc then -- portals that never converted successfully have no viewer_proc
    if not viewer.cfg.detach and not viewer.proc:is_closing() then
      viewer.proc:kill(15)
    end
  end
end

--- Like portal.open but with internal api options
--
---@param pd portal.PortalDescription
local function open_portal(pd)
  pd.src = pd.src or vim.o.filetype

  if pd.dest == nil then
    vim.notify("Portal destination must be provided", vim.log.levels.ERROR, { title = "portal.nvim" })
    return
  end

  local cfg = require("portal.config").cfg_from_pd(pd)

  if cfg == nil then
    vim.notify(
      string.format("No configuration for portal from %s to %s", pd.src, pd.dest),
      vim.log.levels.ERROR,
      { title = "portal.nvim" }
    )
    return
  end

  -- early exit if portal already exists
  if M.is_open(pd) then
    vim.notify(
      string.format("Portal from %s to %s already exists", pd.src, pd.dest),
      vim.log.levels.INFO,
      { title = "portal.nvim" }
    )
    return
  end

  make_viewer(pd)

  if
    cfg.converter == nil -- portal doesn't require a converter
    or get_converter(pd) ~= nil -- converter already exists (from another portal type)
  then
    view(pd)
  elseif pd.bufnr ~= nil then
    -- only make converter for local portals, because global portals will handle it on switch
    make_converter(pd)
    convert(pd) -- initial conversion

    if cfg.converter.daemon then
      view(pd)
    end
  end

  vim.notify(
    string.format("Portal from %s to %s successfully opened", pd.src, pd.dest),
    vim.log.levels.INFO,
    { title = "portal.nvim" }
  )
end

--- Like portal.close but with internal api options
--
---@param pd portal.PortalDescription
local function close_portal(pd)
  pd.src = pd.src or vim.o.filetype

  if pd.dest == nil then
    vim.notify("Portal destination must be provided", vim.log.levels.ERROR, { title = "portal.nvim" })
    return
  end

  if not M.is_open(pd) then
    -- vim.notify("Portal from %s to %s is not open", vim.log.levels.INFO, { title = "portal.nvim" })
    return
  end

  local converter_pd = viewer_pd_to_active_converter_pd(pd)
  if converter_pd and #converter_pd_to_active_viewer_pds(converter_pd) == 0 then
    remove_converter(converter_pd)
  end

  remove_viewer(pd)

  vim.notify(
    string.format("Portal from %s to %s successfully closed", pd.src, pd.dest),
    vim.log.levels.INFO,
    { title = "portal.nvim" }
  )
end

--==============================================================================
-- API
--==============================================================================

--- Directory containing all the rendered output files
--
M.outdir = vim.fn.stdpath("cache") .. "/portal"
vim.fn.mkdir(M.outdir, "p")

--- Directory containing all the cached rendered output files
--
M.cache_outdir = M.outdir .. "/cache"
vim.fn.mkdir(M.cache_outdir, "p")

--- Directory to use for temporary files
--
local nvim_tempdir = vim.fs.dirname(vim.fn.tempname())
M.tempdir = nvim_tempdir .. "/portal"
vim.fn.mkdir(M.tempdir, "p")

--- Setup custom portal configurations
--
---@param cfg portal.Config
function M.setup(cfg)
  config = vim.tbl_deep_extend("force", require("portal.config").config, cfg or {})
end

--- Check if a portal is open
--
---@param pd portal.PortalDescription
---@return boolean
function M.is_open(pd)
  return get_viewer(pd) ~= nil
end

--- List open portals
--
-- TODO
function M.list()
  for bufnr, buf_srcs in pairs(open_portals) do
    for src, buf_dests in pairs(buf_srcs) do
      for dest, _ in pairs(buf_dests) do
        if bufnr == -1 then
          print(string.format("Global  %s  %s", src, dest))
        else
          print(string.format("%s  %s  %s", vim.api.nvim_buf_get_name(bufnr), src, dest))
        end
      end
    end
  end
end

--- Open a portal and a respective view to it. If type is "global", bufnr has no effect.
--
---@param pd portal.PortalDescription
function M.open(pd)
  open_portal(pd)
end

--- Close a portal and its view
--
---@param pd portal.PortalDescription
function M.close(pd)
  close_portal(pd)
end

return M
