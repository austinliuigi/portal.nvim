---@alias portal_description { src: string, dest: string, bufnr: integer }

local portal = {}
local config = {}
local utils = require("portal.utils")

local function parse_cmd(cmd, pd)
  local parsed_cmd = {}
  for _, arg in ipairs(utils.eval_if_func(cmd)) do
    local arg_type = type(arg)
    if arg_type == "string" then
      table.insert(parsed_cmd, arg)
    elseif arg_type == "function" then
      table.insert(parsed_cmd, arg(pd))
    end
  end
  return parsed_cmd
end

--- Contains open portals for each buffer
portal._open_portals = utils.default_table()

--- Infile name for a portal
portal.infile = function(pd)
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(pd.bufnr), ":p:h")
  local file = string.format(".portal-buf%s-%s-%s-infile", pd.bufnr, pd.src, pd.dest)
  return string.format("%s/%s", dir, file)
end

--- Outfile name for a portal
portal.outfile = function(pd)
  local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(pd.bufnr), ":p:h")
  local file = string.format(".portal-buf%s-%s-%s-outfile", pd.bufnr, pd.src, pd.dest)
  return string.format("%s/%s", dir, file)
end

--- Setup custom portal configurations
function portal.setup(cfg)
  if vim.tbl_isempty(config) then
    config = require("portal.config")
  end
  config = vim.tbl_deep_extend("force", config, cfg or {})
end

--- Open a portal and a respective view to it
--
---@param pd portal_description format to interpret file as
function portal.open(pd)
  pd.src = pd.src or vim.o.filetype
  pd.bufnr = pd.bufnr or vim.api.nvim_get_current_buf()

  -- early exit if portal already exists
  if not vim.tbl_isempty(portal._open_portals[pd.bufnr][pd.src][pd.dest]) then
    vim.notify("portal: portal from %s to %s already exists", vim.log.levels.INFO)
    return
  end

  local cfg = config.portals[pd.src][pd.dest]
  if vim.tbl_isempty(cfg) then
    vim.notify(
      string.format("portal: missing configuration for portal from %s to %s", pd.src, pd.dest),
      vim.log.levels.ERROR
    )
    return
  end

  local infile = portal.infile(pd)
  if vim.fn.glob(infile) ~= "" then
    vim.notify(string.format("portal: file %s already exists", infile), vim.log.levels.ERROR)
    return
  end

  -- initial conversion (synchronous to make sure output file exists before viewing)
  vim.cmd("silent w! " .. infile)
  local conversion = vim.system(parse_cmd(cfg.convert_cmd, pd), { text = true }):wait()
  if conversion.code > 1 then
    vim.notify(
      string.format("portal: conversion failed, exited with code %s\n\n(stderr) %s", conversion.code, conversion.stderr),
      vim.log.levels.ERROR
    )
    portal.close(pd)
    return
  end

  -- open viewer
  local viewer = vim.system(parse_cmd(cfg.viewer.open_cmd, pd), { text = true, detach = true }, function(obj)
    if obj.code ~= 0 then
      vim.notify(
        string.format("portal: failed to open viewer, exited with code %s\n\n(stderr) %s", obj.code, obj.stderr),
        vim.log.levels.ERROR
      )
      portal.close(pd)
    end
    -- vim.schedule_wrap(vim.api.nvim_buf_call)(pd.bufnr, function()
    --   portal.close(pd)
    -- end)
  end)

  -- update portal
  local busy = false

  local function update()
    busy = true
    vim.cmd("w! " .. infile)
    vim.system(parse_cmd(cfg.convert_cmd, pd), { text = true }, function()
      busy = false
      if cfg.viewer.refresh_cmd then
        vim.system(parse_cmd(cfg.viewer.refresh_cmd, pd), { text = true })
      end
    end)
  end

  local throttled_update = utils.throttle(update, cfg.throttle_ms)

  local update_autocmd = vim.api.nvim_create_autocmd(cfg.update_events, {
    buffer = pd.bufnr,
    callback = function()
      if not busy then
        if cfg.throttle_ms then
          update()
        else
          throttled_update()
        end
      end
    end,
  })

  -- close portal when no longer needed
  local close_autocmd = vim.api.nvim_create_autocmd({ "BufFilePre", "BufDelete", "VimLeavePre" }, {
    buffer = pd.bufnr,
    callback = function()
      portal.close(pd)
    end,
  })

  -- add entry to list of open portals
  portal._open_portals[pd.bufnr][pd.src][pd.dest] = {
    viewer = viewer,
    autocmds = { update_autocmd, close_autocmd },
  }
end

--- Close a portal and its view
function portal.close(pd)
  local bufnr = vim.api.nvim_get_current_buf()
  local p = portal._open_portals[pd.bufnr][pd.src][pd.dest]

  vim.notify(
    string.format("portal: closing buffer %d'sportal from %s to %s", pd.bufnr, pd.src, pd.dest),
    vim.log.levels.INFO
  )

  -- remove files
  local infile = portal.infile(pd)
  if not vim.uv.fs_unlink(infile) then
    vim.notify(string.format("portal: could not remove file %s", infile), vim.log.levels.ERROR)
  end

  local outfile = portal.outfile(pd)
  if not vim.uv.fs_unlink(outfile) then
    vim.notify(string.format("portal: could not remove file %s", outfile), vim.log.levels.ERROR)
  end

  -- remove autocmds for buffer
  for _, autocmd in ipairs(p.autocmds) do
    vim.api.nvim_del_autocmd(autocmd)
  end

  -- kill view
  print(p.viewer.pid)
  p.viewer:kill(15)

  -- remove entry
  portal._open_portals[pd.bufnr][pd.src][pd.dest] = nil
end

return portal
