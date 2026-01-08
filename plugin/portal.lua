vim.api.nvim_create_user_command("PortalList", function(opts)
  require("portal").list()
end, { nargs = 0 })

vim.api.nvim_create_user_command("PortalOpen", function(opts)
  local bufnr = nil
  if opts.bang then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if #opts.fargs == 1 then
    require("portal").open({
      bufnr = bufnr,
      dest = opts.fargs[1],
    })
  elseif #opts.fargs == 2 then
    require("portal").open({
      bufnr = bufnr,
      src = opts.fargs[1],
      dest = opts.fargs[2],
    })
  end
end, {
  nargs = "*",
  bang = true,
})

vim.api.nvim_create_user_command("PortalClose", function(opts)
  local bufnr = nil
  if opts.bang then
    bufnr = vim.api.nvim_get_current_buf()
  end

  if #opts.fargs == 1 then
    require("portal").close({
      bufnr = bufnr,
      dest = opts.fargs[1],
    })
  elseif #opts.fargs == 2 then
    require("portal").close({
      bufnr = bufnr,
      src = opts.fargs[1],
      dest = opts.fargs[2],
    })
  end
end, {
  nargs = "*",
  bang = true,
})
