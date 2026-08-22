# win11-post-install

Interactive utility to prepare a clean Windows installation. Installs WinGet
and Microsoft Store (which Windows 11 IoT LTSC does not include), lets you
pick which applications to install from a catalog, and runs additional
installers that are not available in WinGet.

## Scope and compatibility

This utility is designed for **Windows 11 IoT LTSC**. It *might* work on
other editions of Windows (or not).

## What it does

- WinGet bootstrap (App Installer) from the official Microsoft release.
- Microsoft Store installation.
- Catalog of WinGet-installable applications, selectable interactively.
- User-defined extras installable with arbitrary commands (e.g., `pip`).
- Dry-run mode that installs and modifies nothing (may be removed in the
  future).

## Requirements

- Windows 11 IoT LTSC (primary target).
- PowerShell 5.1 (included in Windows).
- Administrator privileges for real mode (the script requests them
  automatically).
- Internet connection to download WinGet and applications.
- Python pre-installed if you want to use extras that depend on it
  (e.g., Jupyter).

## Usage

Double-click `win11-post-install.bat`, or from a PowerShell console:

```
.\win11-post-install.ps1
```

On startup you are asked to pick an execution mode:

- **Real mode**: actually installs (requests admin elevation).
- **Dry-run**: simulation; shows the commands that would be run without
  installing anything.

After that, a main menu appears that you navigate with the arrow keys. The
workflow is non-linear: you can enter and leave each section in any order, as
many times as you want, until you choose `Exit`.

## Controls

| Key | Action |
| --- | --- |
| Up/Down arrows | Move between options |
| ENTER | Select option / confirm |
| SPACE | Toggle an application on or off |
| A | Select all |
| N | Deselect all |
| ESC | Go back or exit |

## Menu sections

1. **Utilities**: WinGet bootstrap and Microsoft Store installation.
2. **Applications**: catalog checklist; confirming installs the selected
   apps with WinGet.
3. **Extras**: checklist of extras defined in `extras.json`.
4. **Exit**.

## Files

| File | Description |
| --- | --- |
| `win11-post-install.ps1` | Main logic (modes, menus, installation). |
| `win11-post-install.bat` | Minimal launcher for double-click. |
| `winget-packages.json` | Application catalog (WinGet export format). |
| `extras.json` | Installers outside of WinGet. |

## Adding applications to the catalog

The catalog is read from `winget-packages.json`. To add an application:

1. Add its `PackageIdentifier` to `winget-packages.json`.
2. Optionally, add an entry to the `$AppMeta` table inside
   `win11-post-install.ps1` to give it a friendly name and a category.

Microsoft Store identifiers (no dot, e.g., `9NKSQGP7F2NH` for WhatsApp)
are detected and installed with `--source msstore`. Everything else uses
`--source winget`.

## Extras (`extras.json`)

`extras.json` is a list of objects with these fields:

| Field | Required | Description |
| --- | --- | --- |
| `id` | Yes | Unique identifier. |
| `name` | Yes | Display name in the menu. |
| `description` | No | Description shown in the menu. |
| `requires` | No | Prerequisite. Validated against `"python"` or `"git"`. |
| `install` | Yes | Command to run for installation. |
| `check` | No | Command to detect if already installed (exit 0 = installed). |
| `choices` | No | Submenu to pick a variant. See below. |
| `inputs` | No | Interactive prompts. See below. |

Included example (Jupyter):

```json
[
    {
        "id": "jupyter",
        "name": "Jupyter",
        "description": "Interactive Python notebooks (requires Python)",
        "requires": "python",
        "install": "python -m pip install jupyter",
        "check": "python -c \"import jupyter\""
    }
]
```

Another example for TeX Live (the Windows installer already includes a
minimal Perl, so no additional prerequisites). The installer archive
(`install-tl.zip`) is downloaded and its `install-tl-windows.bat` is run in
non-interactive mode. The `choices` field shows a submenu to pick a scheme;
the `{choice}` placeholder in `install` is replaced with the selected
option:

```json
{
    "id": "texlive",
    "name": "TeX Live",
    "description": "LaTeX distribution",
    "choices": {
        "label": "Scheme",
        "options": ["medium", "full", "small", "basic", "minimal"]
    },
    "install": "$zip = \"$env:TEMP\\install-tl.zip\"; $dir = \"$env:TEMP\\install-tl-unpacked\"; Invoke-WebRequest -Uri 'https://mirror.ctan.org/systems/texlive/tlnet/install-tl.zip' -OutFile $zip -UseBasicParsing; if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }; Expand-Archive -Path $zip -DestinationPath $dir -Force; $bat = Get-ChildItem -LiteralPath $dir -Filter 'install-tl-windows.bat' -Recurse | Select-Object -First 1; & $bat.FullName -no-gui -no-interaction -scheme scheme-{choice} -texdir 'C:/texlive/2026'",
    "check": "tlmgr --version"
}
```

Available TeX Live schemes are `full`, `medium`, `small`, `basic`, and
`minimal`; `medium` is the most balanced for most users.

### `choices` field

When an extra defines `choices`, an arrow-navigable submenu is shown before
installation to pick one of the options. The `choices` object has two
fields:

| Field | Description |
| --- | --- |
| `label` | Submenu title (e.g., `"Scheme"`). |
| `options` | List of options to choose from. |

The chosen option replaces the `{choice}` text inside the `install` field.
If the user cancels the submenu with ESC, the extra is skipped.

### `inputs` field

When an extra defines `inputs`, each value is prompted via `Read-Host`
before installation. Each element has two fields:

| Field | Description |
| --- | --- |
| `var` | Name of the variable that will receive the value. |
| `prompt` | Text displayed when asking for the value. |

The entered value is assigned to the variable `var` in the script scope, and
the `install` field can reference it as `$var`. If the user leaves the field
empty, the extra is skipped. Example (Git identity configuration):

```json
{
    "id": "git-config",
    "name": "Git: set global identity",
    "description": "Sets user.name and user.email in git config --global (requires Git)",
    "requires": "git",
    "inputs": [
        { "var": "gitname", "prompt": "Name for git (user.name)" },
        { "var": "gitemail", "prompt": "Email for git (user.email)" }
    ],
    "install": "git config --global user.name \"$gitname\"; git config --global user.email \"$gitemail\""
}
```

## TODOs

- Refine menu navigation: functionality is in place, but the user experience
  has rough edges that need polishing.
- For extras:
  - Whisper automatic setup and configuration (specific to my setup, not universal).
  - Toggle Windows animations and transparency effects.
  - Toggle Dark mode
  - Enable performance power plan.
  - Prevent the display from turning off automatically.
  - Show hidden files in File Explorer.
  - Show file extensions in File Explorer.

## Notes

- The WinGet bootstrap downloads the latest release from the official
  `microsoft/winget-cli` repository on GitHub.
- Admin elevation is only requested in real mode and is done by relaunching
  the script itself.
- Install commands use `--silent --disable-interactivity` to avoid prompts.
