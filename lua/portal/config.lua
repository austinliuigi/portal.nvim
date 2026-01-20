local M = {}

--- Get the active configuration for a portal, replacing any string names
--- for viewers or converters with their corresponding tables
--
---@param src string
---@param dest string
---@return portal.PortalConfig?
M.get_portal_config = function(src, dest)
  local cfg = vim.deepcopy(require("portal.utils").tbl_get(M.config.portals, { src, dest }))

  if cfg == nil then
    return nil
  end

  if type(cfg.converter) == "string" then
    cfg.converter = M.config.converters[cfg.converter]
  end

  if type(cfg.viewer) == "string" then
    cfg.viewer = M.config.viewers[cfg.viewer]
  end

  cfg.converter = vim.tbl_extend("keep", cfg.converter, M.default_converter_config)

  cfg.viewer = vim.tbl_extend("keep", cfg.viewer, M.default_viewer_config)

  return cfg
end

--- Default converter configuration
--
M.default_converter_config = {
  stdin = false,
  daemon = false,
  success_condition = { exit_code = 0 },
  failure_condition = {},
}

--- Default viewer configuration
--
M.default_viewer_config = {
  detach = true,
}

--- Default user configuration
--
M.default_config = {
  --=========================================================================
  -- general
  --=========================================================================
  cache_retention_days = 7,

  --=========================================================================
  -- viewers
  --=========================================================================
  viewers = {
    sioyek = {
      open_cmd = { "sioyek", "--instance-name", "$ID", "$OUTFILE" },
      switch_cmd = { "sioyek", "--instance-name", "$ID", "$OUTFILE" },
      detach = false,
    },
    mpv = {
      open_cmd = { "mpv", "--input-ipc-server=$TEMPDIR/$ID.socket", "$OUTFILE" },
      refresh_cmd = { "bash", "-c", 'echo \'{ "command": ["loadfile", "$OUTFILE"] }\' | socat - $TEMPDIR/$ID.socket' },
      switch_cmd = { "bash", "-c", 'echo \'{ "command": ["loadfile", "$OUTFILE"] }\' | socat - $TEMPDIR/$ID.socket' },
      detach = false,
    },
  },

  --=========================================================================
  -- portals
  --=========================================================================
  portals = {
    ---------------------------------------------------------------------------
    -- markdown
    ---------------------------------------------------------------------------
    markdown = {
      -- markdown to html -----------------------------------------------------------------
      html = {
        converter = {
          cmd = {
            "pandoc",
            "--katex",
            "--standalone",
            "-o",
            "$OUTFILE",
          },
          stdin = true,
          daemon = false,
        },
        viewer = {
          open_cmd = { "firefox", "$OUTFILE" },
          refresh_cmd = nil,
          detach = true,
        },
      },
      -- markdown to pdf -----------------------------------------------------------------
      pdf = {
        converter = {
          cmd = {
            "pandoc",
            "--from=markdown",
            "--to=pdf",
            "-o",
            "$OUTFILE",
          },
          stdin = true,
          daemon = false,
        },
        viewer = "sioyek",
      },
      -- markdown to presenterm -----------------------------------------------------------------
      presenterm = {
        converter = nil,
        viewer = {
          open_cmd = { "kitty", "presenterm", "$INFILE" },
          detach = false,
        },
      },
    },
    ---------------------------------------------------------------------------
    -- typst
    ---------------------------------------------------------------------------
    typst = {
      -- typst to pdf -----------------------------------------------------------------
      pdf = {
        converter = {
          cmd = { "typst", "watch", "$INFILE", "$OUTFILE" },
          stdin = false,
          daemon = true,
          success_condition = { stderr_contains = "compiled" },
          failure_condition = { stderr_contains = "error" },
        },
        viewer = "sioyek",
      },
    },
    ---------------------------------------------------------------------------
    -- manim
    -- TODO: run in temp directory?
    ---------------------------------------------------------------------------
    manim = {
      -- manim to png -----------------------------------------------------------------
      png = {
        converter = {
          cmd = { "manim", "--format=png", "$INFILE", "-o", "$OUTFILE" },
          stdin = false,
          daemon = false,
        },
        viewer = "mpv",
      },
      -- manim to gif -----------------------------------------------------------------
      gif = {
        converter = {
          cmd = { "manim", "-ql", "--format=gif", "$INFILE", "-o", "$OUTFILE" },
          stdin = false,
          daemon = false,
        },
        viewer = "mpv",
      },
      -- manim to mp4 -----------------------------------------------------------------
      mp4 = {
        converter = {
          cmd = { "manim", "-ql", "--format=mp4", "$INFILE", "-o", "$OUTFILE" },
          stdin = false,
          daemon = false,
        },
        viewer = "mpv",
      },
    },
  },
}

--- Active user configuration
--
M.config = vim.deepcopy(M.default_config)

return M
