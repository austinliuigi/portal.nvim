# 🌀 portal.nvim

Create portals to view files in different formats.

https://github.com/user-attachments/assets/afb485b0-6f2c-4738-9381-adaac182a475


## Features

- preview actual rendered output while editing
- automatically re-render output on changes
- automatically reload view
- follow active buffer
- cache rendered outputs
<!-- - scroll-sync on supported viewers -->

<!-- foo 
> [!NOTE]
> For scroll sync:
>   1. A conversion between editor position and viewer position needs to be made, e.g. synctex.
>   2. The viewer needs to have an IPC to jump to a position remotely.
-->



## Terminology

**input type**: A name given to an input of a portal. This is typically a filetype (e.g. `markdown`), but doesn't need to be (e.g. `manim`). If the type is a filetype, then it doesn't need to be specified when opening or closing a portal. Non-filetype types need to be explicitly given.

**output type**: A name given to an output of a portal. These correspond to the extension of rendered output file.

**portal**: A link between an input/source type and an output/destination type that _consists of a converter and a viewer_. A portal can exist without a converter if the viewer utilizes the input file itself, e.g. `html` or `presenterm` files.

- **global portal**: A portal that dynamically changes input depending on the focused buffer. Entering a different buffer will cause it to become the input to the portal if its filetype matches the portal's input type. Note that this _only_ works with filetype inputs.

- **local portal**: A portal that is specific to a single buffer only. The input to the portal is the buffer that it was instantiated with, regardless of whether the user navigates to other buffers.

<!-- - **proxy portal**: A portal that delegates to a separate local portal instead of producing its own output. This exists for cases where the file that you want to input to the portal differs from the file you are editing. For example, you are editing file `lib` and want your changes to automatically trigger an update of a local portal attached to the file `main`, which imports `lib`. -->

**converter**: A program used to convert the source filetype to the destination filetype. Converters can be one-shot (e.g. `pandoc`) or daemons (e.g. `typst watch`). Converters can either take input from stdin or files. If a converter takes input from stdin, it updates on `{ TextChanged, TextChangedI }` rather than `BufWritePost`. Note that daemon converters by definition watch for file changes, so they don't take stdin. Therefore, `converter.daemon` and `converter.stdin` are mutually exclusive.

**viewer**: A program used to view a destination filetype. Requires the capability to either remotely refresh the view through an IPC or auto-refresh on file change. For forward scroll-sync, the viewer also needs to have an IPC for scrolling. For reverse scroll-sync, the viewer needs to have the ability to communicate with neovim. For global portals, the viewer needs to have an IPC for switching to a different file.

- **attached viewers**: Attached viewers automatically close when the portal is closed. When the portal is closed, the viewer is closed. When the viewer is closed, the portal is closed.

- **detached viewers**: Detached viewers and their corresponding portals need to be manually closed. When a portal is closed, the viewer is not closed. When the viewer is closed, the portal is not closed. Should be used for viewers that could potentially hook into an already running process, e.g. firefox.



## Installation

portal.nvim can be installed like any other plugin

<details>
  <summary>lazy.nvim</summary>

```lua
{
  'austinliuigi/portal.nvim',
  opts = {},
}
```

For a more thorough configuration involving lazy-loading, see [Lazy loading with lazy.nvim](doc/recipes.md#lazy-loading-with-lazynvim).

</details>

<details>
  <summary>Packer</summary>

```lua
require("packer").startup(function()
  use({
    "austinliuigi/portal.nvim",
    config = function()
      require("portal").setup()
    end,
  })
end)
```

</details>

<details>
  <summary>Paq</summary>

```lua
require("paq")({
  { "austinliuigi/portal.nvim" },
})
```

</details>

<details>
  <summary>vim-plug</summary>

```vim
Plug 'austinliuigi/portal.nvim'
```

</details>

<details>
  <summary>dein</summary>

```vim
call dein#add('austinliuigi/portal.nvim')
```

</details>

<details>
  <summary>Pathogen</summary>

```sh
git clone --depth=1 https://github.com/austinliuigi/portal.nvim.git ~/.vim/bundle/
```

</details>

<details>
  <summary>Neovim native package</summary>

```sh
git clone --depth=1 https://github.com/austinliuigi/portal.nvim.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/portal/start/portal.nvim
```

</details>



## Usage


### Opening portals

```
:PortalOpen[!] [input_type] <output_type>
```

Opens a portal and viewer to the desired format. By default, a local portal attached to the current buffer is opened. If `!` is supplied, then a global portal is opened.

`input_type`: filetype, *optional*
- The input filetype of the portal to open. Default is the current buffer's filetype.

`output_type`: filetype
- The output filetype of the portal to open.


### Closing portals

```
:PortalClose[!] [input_type] <output_type>
```

Closes a portal matching the given arguments. By default, a global portal is closed. If `!` is supplied, then a local portal attached to the current buffer is closed.
If no matching portal is found, it exits silently.

`input_type`: filetype, *optional*
- The input filtype type of the portal to close. Default is the current buffer's filetype.

`output_type`: filetype
- The output filtype type of the portal to close.


<!-- ### Opening proxy portal -->
<!---->
<!-- ``` -->
<!-- :PortalProxy <main_file> [input_type] <output_type> -->
<!-- ``` -->
<!---->
<!-- Create a proxy to a local portal attached to `<main_file>`. If the local portal doesn't exist, create it. -->


### Listing portals

```
:PortalList
```

Lists all open portals.


### Viewing Logs

```
:PortalLog [input_type] <output_type>
```

Opens a buffer containing the output of the converter process used by any portals in the current buffer matching the given arguments.



## Configuration

<!-- - [ ] document portals that require no converter, e.g. `presenterm` -->
<!-- - [ ] only viewers that don't auto-reload on file-change need to set `refresh_cmd` -->
<!-- - [ ] document cmd variables -->

### Example Config

```lua
require("portal").setup({
  cache_retention_days = 7, -- remove cache entries older than this number of days
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
  portals = {
    markdown = {
      -- markdown to pdf -----------
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
    }
    typst = {
      -- typst to pdf -----------
      pdf = {
        converter = {
          cmd = { "typst", "watch", "$INFILE", "$OUTFILE" },
          stdin = false,
          daemon = true,
          success_condition = { stderr_contains = "compiled", },
          failure_condition = { stderr_contains = "error", },
        },
        viewer = "sioyek",
      },
    },
    manim = {
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
  }
})
```

### Converters

| Option              | Type                                | Description |
|---------------------|-------------------------------------|-------------|
| `cmd`               | `portal.CmdConfig`                  | Command used to generate output file. If function, it is evaluated once when the converter is created to get the command table. If any arguments are functions, they will be evaluated on each invocation of `cmd`. |
| `stdin`             | `boolean`                           | True if `cmd` uses stdin as its input. |
| `daemon`            | `boolean`                           | True if `cmd` creates a long-running daemon process which triggers a conversion on file changes. |
| `success_condition` | `portal.ConverterSuccessConditions` | Condition that indicates a conversion succeeded in generating an output. By default, an exit code of 0 indicates a success. Daemon converters should set either `stdout_contains` or `stderr_contains`. |
| `failure_condition` | `portal.ConverterFailureConditions` | Condition that indicates a conversion failed in generating an output. If `success_condition` contains `exit_code`, then the inverse is used to indicate a failure. Otherwise, either `stdout_contains` or `stderr_contains` should be set. |


### Viewers

| Option        | Type               | Description |
|---------------|--------------------|-------------|
| `open_cmd`    | `portal.CmdConfig` | Command used to open viewer process. |
| `refresh_cmd` | `portal.CmdConfig` | Command used to refresh file that is being viewed. |
| `switch_cmd`  | `portal.CmdConfig` | Command used to switch file that is being viewed. |
| `detach`      | `boolean`          | True if viewer should be "detached" from portal. Detached viewers need to be manually closed. |
