#!/usr/bin/env go
//
// mumu-menu-cmd — CLI facade for mumu-menu.ps1.
//
// Build:
//   go build -o mumu-menu-cmd ./cmd/mumu-menu-cmd
//
// Usage (pick exactly one top-level verb):
//   mumu-menu-cmd run            interactive menu (default)
//   mumu-menu-cmd run --once    one-shot mode: render menu once, exit 0
//   mumu-menu-cmd start [--index N] [--restore]   launch + wait for boot
//   mumu-menu-cmd wait [--index N] [--timeout s]  poll until android_started
//   mumu-menu-cmd status        machine-readable instance table (JSON)
//
// Environment:
//   MUUMU_EXE        path to MuMuManager.exe (defaults to an adjacent search)
//   MUUMU_INDEX      default instance index for verbs that need one
//   MUUMU_RESTORE    "1" enables --restore behaviour by default
//
// All verbs use the same PS invocation that the tray/menu path already uses
// (`powershell -NoProfile -ExecutionPolicy Bypass -File mumu-menu.ps1 ...`),
// so this is just a thin dispatcher + helper serialization — no new MuMu
// logic and no new interpreter path.

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "mumu-menu-cmd: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	verb, rest, err := splitVerb(args)
	if err != nil {
		return err
	}
	switch verb {
	case "run":
		return runMenu(rest)
	case "start":
		return startEmulator(rest)
	case "wait":
		return waitForBoot(rest)
	case "status":
		return statusTree(rest)
	default:
		return fmt.Errorf("unknown verb %q; expected run|start|wait|status", verb)
	}
}

func splitVerb(args []string) (string, []string, error) {
	if len(args) == 0 {
		return "run", nil, nil
	}
	v := args[0]
	switch v {
	case "run", "start", "wait", "status":
		return v, args[1:], nil
	case "-h", "--help", "help":
		printHelp()
		os.Exit(0)
	default:
		return "", nil, fmt.Errorf("unknown verb %q; expected run|start|wait|status", v)
	}
}

func printHelp() {
	fmt.Println(`Usage: mumu-menu-cmd <verb> [options]

Verbs:
  run            Start the interactive menu (default).
  run --once     One-shot mode: render the menu once and exit 0.
  start [--index N] [--restore]
                 Launch the instance and wait for boot.
  wait [--index N] [--timeout s]
                 Poll until android_started (default timeout 120s).
  status         Print a machine-readable instance/status tree (JSON).

Environment:
  MUUMU_EXE      path to MuMuManager.exe
  MUUMU_INDEX    default instance index
  MUUMU_RESTORE  set to "1" to prefer --restore by default
`)
}

func psScriptDir() (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	candidate := filepath.Join(cwd, "mumu-menu.ps1")
	if _, err := os.Stat(candidate); err == nil {
		return cwd, nil
	}
	// Fallback: walk up to 3 parent levels for a repo checkout.
	dir := cwd
	for i := 0; i < 3; i++ {
		candidate = filepath.Join(dir, "mumu-menu.ps1")
		if _, err := os.Stat(candidate); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", fmt.Errorf("mumu-menu.ps1 not found under %s (set MUUMU_SCRIPT_DIR)", cwd)
}

func psExe() (string, error) {
	names := []string{"powershell", "pwsh"}
	for _, n := range names {
		path, err := exec.LookPath(n)
		if err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("neither powershell.exe nor pwsh.exe found on PATH")
}

func buildPSArgs(verb string, rest []string) ([]string, error) {
	scriptDir, err := psScriptDir()
	if err != nil {
		return nil, err
	}
	exe, err := psExe()
	if err != nil {
		return nil, err
	}

	base := []string{
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", filepath.Join(scriptDir, "mumu-menu.ps1"),
	}

	switch verb {
	case "run":
		base = append(base, "Run-Menu")
		for _, r := range rest {
			if strings.EqualFold(r, "--once") {
				base = append(base, "--once")
			}
		}
	case "start":
		base = append(base, "Start-Emulator")
		idx, restore := parseStartFlags(rest)
		if idx != nil {
			base = append(base, "--index", fmt.Sprint(*idx))
		}
		if restore {
			base = append(base, "--restore")
		}
	case "wait":
		base = append(base, "Wait-ForBoot")
		idx, timeout := parseWaitFlags(rest)
		if idx != nil {
			base = append(base, "--index", fmt.Sprint(*idx))
		}
		if timeout != nil {
			base = append(base, "--timeout", fmt.Sprint(*timeout))
		}
	case "status":
		base = append(base, "Get-StatusTree")
		idx, deep := parseStatusFlags(rest)
		if idx != nil {
			base = append(base, "--index", fmt.Sprint(*idx))
		}
		if deep {
			base = append(base, "--deep")
		}
	}

	return append([]string{exe}, base...), nil
}

func runMenu(rest []string) error {
	args, err := buildPSArgs("run", rest)
	if err != nil {
		return err
	}
	return runPS(args)
}

func startEmulator(rest []string) error {
	args, err := buildPSArgs("start", rest)
	if err != nil {
		return err
	}
	return runPS(args)
}

func waitForBoot(rest []string) error {
	args, err := buildPSArgs("wait", rest)
	if err != nil {
		return err
	}
	return runPS(args)
}

func statusTree(rest []string) error {
	args, err := buildPSArgs("status", rest)
	if err != nil {
		return err
	}
	out, err := runPSOutput(args)
	if err != nil {
		return err
	}
	var st statusOutput
	if err := json.Unmarshal([]byte(out), &st); err != nil {
		return fmt.Errorf("status JSON parse failed: %w", err)
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(st); err != nil {
		return err
	}
	return nil
}

func runPS(args []string) error {
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func runPSOutput(args []string) (string, error) {
	cmd := exec.Command(args[0], args[1:]...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("ps exit %d: %s", exitCode(err), strings.TrimSpace(stderr.String()))
	}
	return strings.TrimSpace(stdout.String()), nil
}

func exitCode(err error) int {
	if ee, ok := err.(*exec.ExitError); ok {
		if s, ok := ee.Sys().(interface{ ExitStatus() int }); ok {
			return s.ExitStatus()
		}
	}
	return 1
}

// ---------------------------------------------------------------------------
// flag helpers
// ---------------------------------------------------------------------------

func parseStartFlags(rest []string) (*int, bool) {
	var idx *int
	var restore bool
	for i := 0; i < len(rest); i++ {
		switch strings.EqualFold(rest[i], "--index") {
		case true:
			if i+1 < len(rest) {
				v, err := parseIndex(rest[i+1])
				if err == nil {
					idx = &v
				}
				i++
			}
		case "--restore":
			restore = true
		}
	}
	if idx == nil {
		if v, ok := os.LookupEnv("MUUMU_INDEX"); ok {
			if iv, err := parseIndex(v); err == nil {
				idx = &iv
			}
		}
	}
	if restore == false {
		if os.Getenv("MUUMU_RESTORE") == "1" {
			restore = true
		}
	}
	return idx, restore
}

func parseWaitFlags(rest []string) (*int, *int) {
	var idx *int
	var timeout *int
	for i := 0; i < len(rest); i++ {
		switch strings.EqualFold(rest[i], "--index") {
		case true:
			if i+1 < len(rest) {
				v, err := parseIndex(rest[i+1])
				if err == nil {
					idx = &v
				}
				i++
			}
		case "--timeout":
			if i+1 < len(rest) {
				v, err := parsePositiveInt(rest[i+1])
				if err == nil {
					timeout = &v
				}
				i++
			}
		}
	}
	if idx == nil {
		if v, ok := os.LookupEnv("MUUMU_INDEX"); ok {
			if iv, err := parseIndex(v); err == nil {
				idx = &iv
			}
		}
	}
	return idx, timeout
}

func parseStatusFlags(rest []string) (*int, bool) {
	var idx *int
	var deep bool
	for i := 0; i < len(rest); i++ {
		switch strings.EqualFold(rest[i], "--index") {
		case true:
			if i+1 < len(rest) {
				v, err := parseIndex(rest[i+1])
				if err == nil {
					idx = &v
				}
				i++
			}
		case "--deep":
			deep = true
		}
	}
	if idx == nil {
		if v, ok := os.LookupEnv("MUUMU_INDEX"); ok {
			if iv, err := parseIndex(v); err == nil {
				idx = &iv
			}
		}
	}
	return idx, deep
}

func parseIndex(s string) (int, error) {
	n, err := parsePositiveInt(s)
	if err != nil {
		return 0, fmt.Errorf("invalid --index %q", s)
	}
	return n, nil
}

func parsePositiveInt(s string) (int, error) {
	v, err := fmt.Sscanf(s, "%d", new(int))
	if err != nil || v != 1 {
		return 0, fmt.Errorf("not an integer: %q", s)
	}
	var out int
	fmt.Sscanf(s, "%d", &out)
	if out < 1 {
		return 0, fmt.Errorf("must be >= 1: %q", s)
	}
	return out, nil
}

// ---------------------------------------------------------------------------
// status output shape
// ---------------------------------------------------------------------------

type statusOutput struct {
	ScriptVersion string            `json:"scriptVersion"`
	MuMuVersion   string            `json:"muMuVersion"`
	Instances     []statusInstance  `json:"instances"`
}

type statusInstance struct {
	Index      string   `json:"index"`
	Name       string   `json:"name"`
	PlayerState string  `json:"playerState"`
	Running    bool     `json:"running"`
	AndroidStarted bool `json:"androidStarted"`
}
