vim.api.nvim_create_user_command("PortalList", function(opts)
  require("portal").list()
end, { nargs = 0 })

vim.api.nvim_create_user_command("PortalOpen", function(opts)
  local bufnr = nil
  if opts.bang then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if #opts.fargs == 1 then
    require("portal").open(nil, opts.fargs[1], bufnr)
  elseif #opts.fargs == 2 then
    require("portal").open(opts.fargs[1], opts.fargs[2], bufnr)
  end
end, {
  nargs = "*",
  bang = true,
  complete = function(arglead, cmdline, cursorpos)
    local args = vim.split(cmdline, "%s+", { trimempty = true })
    table.remove(args, 1) -- remove command name

    local arg_index = #args
    if cmdline:sub(cursorpos, cursorpos):match("%s") then
      arg_index = arg_index + 1
    end

    local completions = {}
    local portal_configs = require("portal.config").config.portals

    -- completion for first argument --------------------
    if arg_index == 1 then
      -- add destinations of portals whose source is the current filetype
      completions = vim.tbl_keys(portal_configs[vim.o.filetype] or {})
      -- add all configured sources
      vim.list_extend(completions, vim.tbl_keys(portal_configs))

    -- completion for first argument --------------------
    elseif arg_index == 2 then
      -- add destinations of portals whose source is the first argument
      completions = vim.tbl_keys(portal_configs[args[1]] or {})
    end

    return completions
  end,
})

vim.api.nvim_create_user_command("PortalClose", function(opts)
  local bufnr = nil
  if opts.bang then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if #opts.fargs == 1 then
    require("portal").close(nil, opts.fargs[1], bufnr)
  elseif #opts.fargs == 2 then
    require("portal").close(opts.fargs[1], opts.fargs[2], bufnr)
  end
end, {
  nargs = "*",
  bang = true,
  complete = function(arglead, cmdline, cursorpos)
    local args = vim.split(cmdline, "%s+", { trimempty = true })
    local cmd = table.remove(args, 1) -- remove command name
    local bang = cmd:sub(#cmd) == "!"

    local arg_index = #args
    if cmdline:sub(cursorpos, cursorpos):match("%s") then
      arg_index = arg_index + 1
    end

    local completions = {}

    -- local portals ------------------------------
    if bang then
      local curr_buf_instances = require("portal.classes.LocalViewer").instances[vim.api.nvim_get_current_buf()] or {}
      -- completion for first argument ----------
      if arg_index == 1 then
        -- add destinations of open local portals attached to the current buffer whose source is the current filetype
        completions = vim.tbl_keys(curr_buf_instances[vim.o.filetype] or {})
        -- add sources of open local portals attached to the current buffer
        vim.list_extend(completions, vim.tbl_keys(curr_buf_instances))

        -- completion for second argument ----------
      elseif arg_index == 2 then
        -- add destinations of open portals whose source is the first argument
        completions = vim.tbl_keys(curr_buf_instances[args[1]] or {})
      end

    -- global portals ------------------------------
    else
      local global_instances = require("portal.classes.GlobalViewer").instances
      -- completion for first argument ----------
      if arg_index == 1 then
        -- add destinations of open local portals attached to the current buffer whose source is the current filetype
        completions = vim.tbl_keys(global_instances[vim.o.filetype] or {})
        -- add sources of open local portals attached to the current buffer
        vim.list_extend(completions, vim.tbl_keys(global_instances))

      -- completion for second argument ----------
      elseif arg_index == 2 then
        -- add destinations of open portals whose source is the first argument
        completions = vim.tbl_keys(global_instances[args[1]] or {})
      end
    end
    return completions
  end,
})

vim.api.nvim_create_user_command("PortalLog", function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local src
  local dest

  if #opts.fargs == 1 then
    src = vim.o.filetype
    dest = opts.fargs[1]
  elseif #opts.fargs == 2 then
    src = opts.fargs[1]
    dest = opts.fargs[2]
  end

  local converter = require("portal.utils").tbl_get(require("portal.classes.Converter").instances, { bufnr, src, dest })
  if converter == nil then
    return
  end

  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, converter.log_buf.bufnr)
end, {
  nargs = "*",
  complete = function(arglead, cmdline, cursorpos)
    local args = vim.split(cmdline, "%s+", { trimempty = true })
    local cmd = table.remove(args, 1) -- remove command name

    local arg_index = #args
    if cmdline:sub(cursorpos, cursorpos):match("%s") then
      arg_index = arg_index + 1
    end

    local completions = {}

    local curr_buf_instances = require("portal.classes.Converter").instances[vim.api.nvim_get_current_buf()] or {}
    -- completion for first argument ----------
    if arg_index == 1 then
      -- add destinations of open local portals attached to the current buffer whose source is the current filetype
      completions = vim.tbl_keys(curr_buf_instances[vim.o.filetype] or {})
      -- add sources of open local portals attached to the current buffer
      vim.list_extend(completions, vim.tbl_keys(curr_buf_instances))

      -- completion for second argument ----------
    elseif arg_index == 2 then
      -- add destinations of open portals whose source is the first argument
      completions = vim.tbl_keys(curr_buf_instances[args[1]] or {})
    end

    return completions
  end,
})
