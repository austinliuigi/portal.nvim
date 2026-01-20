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

    if arg_index == 1 then
      return vim.tbl_keys(require("portal.config").config.portals)
    elseif arg_index == 2 then
      return vim.tbl_keys(require("portal.config").config.portals[args[1]])
    end
    return {}
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
    if arg_index == 1 then
      if bang then
        for src, dest_tbl in pairs(require("portal.classes.LocalViewer").instances) do
          for dest, bufnr_tbl in pairs(dest_tbl) do
            for bufnr, _ in pairs(bufnr_tbl) do
              if bufnr == vim.api.nvim_get_current_buf() then
                table.insert(completions, src)
                break
              end
            end
          end
        end
      else
        completions = vim.tbl_keys(require("portal.classes.GlobalViewer").instances)
      end
    elseif arg_index == 2 then
      if bang then
        for src, dest_tbl in pairs(require("portal.classes.LocalViewer").instances) do
          for dest, bufnr_tbl in pairs(dest_tbl) do
            for bufnr, _ in pairs(bufnr_tbl) do
              if bufnr == vim.api.nvim_get_current_buf() then
                table.insert(completions, dest)
                break
              end
            end
          end
        end
      else
        completions = vim.tbl_keys(require("portal.classes.GlobalViewer").instances[args[1]])
      end
    end
    return completions
  end,
})
