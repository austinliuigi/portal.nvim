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

  -- initial conversion
  vim.system(
    parse_cmd(cfg.convert_cmd, pd),
    { stdin = vim.api.nvim_buf_get_lines(0, 0, -1, false), text = true },
    vim.schedule_wrap(function(conversion)
      if conversion.code > 1 then
        vim.notify(
          string.format(
            "portal: conversion failed, exited with code %s\n\n(stderr) %s",
            conversion.code,
            conversion.stderr
          ),
          vim.log.levels.ERROR
        )
        return
      end

      vim.notify(
        string.format("portal: portal from %s to %s successfully opened", pd.src, pd.dest),
        vim.log.levels.INFO
      )

      -- open viewer
      entry.viewer = vim.system(
        parse_cmd(cfg.viewer.open_cmd, pd),
        { text = true, detach = true },
        vim.schedule_wrap(function(obj)
          if obj.code ~= 0 then
            vim.notify(
              string.format("portal: failed to open viewer, exited with code %s\n\n(stderr) %s", obj.code, obj.stderr),
              vim.log.levels.ERROR
            )
          end
          if cfg.viewer.attach then
            vim.api.nvim_buf_call(pd.bufnr, function()
              portal.close(pd)
            end)
          end
        end)
      )

      -- update portal
      local busy, queue = false, false
      local function update()
        busy = true
        vim.system(
          parse_cmd(cfg.convert_cmd, pd),
          { stdin = vim.api.nvim_buf_get_lines(0, 0, -1, false), text = true },
          vim.schedule_wrap(function()
            busy = false
            if cfg.viewer.refresh_cmd then
              vim.system(parse_cmd(cfg.viewer.refresh_cmd, pd), { text = true })
            end
            if queue then
              queue = false
              update()
            end
          end)
        )
      end

      entry.update_autocmd = vim.api.nvim_create_autocmd(cfg.update_events, {
        buffer = pd.bufnr,
        callback = function()
          if busy then
            queue = true
          else
            update()
          end
        end,
      })

      -- close portal when no longer needed
      vim.api.nvim_create_autocmd({ "BufFilePre", "BufDelete", "VimLeavePre" }, {
        buffer = pd.bufnr,
        callback = function()
          portal.close(pd)
        end,
        once = true,
      })
    end)
  )
end

--- Close a portal and its view
function portal.close(pd)
  pd.src = pd.src or vim.o.filetype
  pd.bufnr = pd.bufnr or vim.api.nvim_get_current_buf()

  local entry = portal._open_portals[pd.bufnr][pd.src][pd.dest]
  if vim.tbl_isempty(entry) then
    vim.notify("portal: portal from %s to %s is not open", vim.log.levels.INFO)
    return
  end

  local outfile = portal.outfile(pd)
  if not vim.uv.fs_unlink(outfile) then
    vim.notify(string.format("portal: could not remove file %s", outfile), vim.log.levels.ERROR)
  end

  vim.api.nvim_del_autocmd(entry.update_autocmd)

  -- kill view
  print(p.viewer.pid)
  p.viewer:kill(15)

  -- remove entry
  entry = {}

  vim.notify(string.format("portal: portal from %s to %s successfully closed", pd.src, pd.dest), vim.log.levels.INFO)
end

return portal
