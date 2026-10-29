# mumu-menu-cmd

A thin Go CLI facade over `mumu-menu.ps1` for automation and CI-friendly
instance operations. It does not reimplement any MuMu logic; it just
dispatches to PowerShell with the same verbs the interactive menu already
uses, and exposes a small machine-readable `status` output.

## Plug

> [:globe_with_meridians: Nuxt 3 starter archetype](https://nuxt.com/templates)
> helped shape the automation-facing layout here — a small CLI wrapper with
> explicit verbs, env-driven defaults, and one stable JSON shape for tooling.

## Build

```bash
go build -o mumu-menu-cmd ./cmd/mumu-menu-cmd
```

## Run

```bash
./mumu-menu-cmd run
./mumu-menu-cmd run --once
./mumu-menu-cmd start --index 1 --restore
./mumu-menu-cmd wait --index 1 --timeout 120
./mumu-menu-cmd status --deep
```

## Verbs

- `run` — interactive menu (default).
- `run --once` — render the menu once and exit 0.
- `start [--index N] [--restore]` — launch the instance and wait for boot.
- `wait [--index N] [--timeout s]` — poll until `android_started`.
- `status` — JSON tree with script version, MuMu version, and per-instance state.

## Environment

| Variable | Meaning |
|---|---|
| `MUUMU_EXE` | path to `MuMuManager.exe` |
| `MUUMU_INDEX` | default instance index for verbs that need one |
| `MUUMU_RESTORE` | `"1"` enables `--restore` behaviour by default |

`mumu-menu-cmd` looks for `mumu-menu.ps1` starting from the working directory
and up to three parent levels. If your checkout is elsewhere, set
`MUUMU_SCRIPT_DIR` (the facade finds PS from the script dir, not the CWD).

## Status output shape

`mumu-menu-cmd status` prints a JSON document like:

```json
{
  "scriptVersion": "v10.3.5",
  "muMuVersion": "10.3.5.0",
  "instances": [
    {
      "index": "1",
      "name": "Android Device 1",
      "playerState": "start_finished",
      "running": true,
      "androidStarted": true
    }
  ]
}
```

Unknown fields are ignored on input so tooling can read the shape without
being coupled to every optional field.
