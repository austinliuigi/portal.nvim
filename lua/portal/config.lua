local M = {}

--- Get the configuration for a portal, replacing any string names for
--- viewers or converters with their corresponding tables
--
---@param pd portal.PortalDescription
M.cfg_from_pd = function(pd)
  if not require("portal.utils").tbl_contains(M.config.portals, { pd.src, pd.dest }) then
    return nil
  end

  local cfg = vim.deepcopy(config.portals[pd.src][pd.dest])

  if type(cfg.converter) == "string" then
    cfg.converter = config.converters[cfg.converter]
  end

  if type(cfg.viewer) == "string" then
    cfg.viewer = config.viewers[cfg.viewer]
  end

  return cfg
end

-- The default user configuration
M.default_config = {
  --=========================================================================
  -- viewers
  --=========================================================================
  viewers = {
    sioyek = {
      open_cmd = { "sioyek", "$OUTFILE" },
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
      -- html -----------------------------------------------------------------
      html = {
        converter = {
          cmd = {
            "pandoc",
            "--katex",
            "--standalone",
            "-o",
            "$OUTFILE",
          },
          daemon = false,
          stdin = true,
        },
        viewer = {
          open_cmd = { "firefox", "$OUTFILE" },
          refresh_cmd = nil,
          detach = true,
        },
      },
      -- pdf -----------------------------------------------------------------
      pdf = {
        converter = {
          cmd = {
            "pandoc",
            "--from=markdown",
            "--to=pdf",
            "-o",
            "$OUTFILE",
          },
          daemon = false,
          stdin = true,
        },
        viewer = "sioyek",
      },
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
      -- pdf -----------------------------------------------------------------
      pdf = {
        converter = {
          cmd = { "typst", "watch", "$INFILE", "$OUTFILE" },
          daemon = true,
          stdin = false,
        },
        viewer = "sioyek",
      },
    },
    ---------------------------------------------------------------------------
    -- manm
    ---------------------------------------------------------------------------
    manim = {
      -- png -----------------------------------------------------------------
      png = {
        converter = {
          cmd = { "manim", "--format=png", "$INFILE", "-o", "$OUTFILE" },
          daemon = false,
          stdin = false,
        },
      },
      -- gif -----------------------------------------------------------------
      gif = {
        converter = {
          cmd = { "manim", "-ql", "--format=gif", "$INFILE", "-o", "$OUTFILE" },
          daemon = false,
          stdin = false,
        },
      },
      -- mp4 -----------------------------------------------------------------
      mp4 = {
        converter = {
          cmd = { "manim", "-ql", "--format=mp4", "$INFILE", "-o", "$OUTFILE" },
          daemon = false,
          stdin = false,
        },
      },
    },
  },
}

-- The active user configuration
M.config = vim.deepcopy(M.default_config)

return M
