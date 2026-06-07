package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// hasBuildScript reports whether dir contains the karabiner build script under
// either its chezmoi-source name (executable_build.sh) or its deployed name
// (build.sh).
func hasBuildScript(dir string) bool {
	for _, n := range []string{"build.sh", "executable_build.sh"} {
		if _, err := os.Stat(filepath.Join(dir, n)); err == nil {
			return true
		}
	}
	return false
}

// resolveSourceDir returns the chezmoi *source* path of the karabiner config dir,
// so edits are tracked and `chezmoi apply` deploys them.
// Order: $ADDKEYMAP_SOURCE override, then `chezmoi source-path ~/.config/karabiner`,
// then two levels up from the running binary. Each candidate must contain the
// build script (build.sh or executable_build.sh).
func resolveSourceDir() (string, error) {
	// Explicit override (used for testing / non-standard setups).
	if env := os.Getenv("ADDKEYMAP_SOURCE"); env != "" {
		if hasBuildScript(env) {
			return env, nil
		}
		return "", fmt.Errorf("ADDKEYMAP_SOURCE=%q has no build.sh / executable_build.sh", env)
	}
	home, _ := os.UserHomeDir()
	target := filepath.Join(home, ".config", "karabiner")
	out, err := exec.Command("chezmoi", "source-path", target).Output()
	if err == nil {
		dir := strings.TrimSpace(string(out))
		if dir != "" && hasBuildScript(dir) {
			return dir, nil
		}
	}
	exe, exeErr := os.Executable()
	if exeErr == nil {
		cand := filepath.Dir(filepath.Dir(exe)) // scripts/ -> karabiner/
		if hasBuildScript(cand) {
			return cand, nil
		}
	}
	return "", fmt.Errorf("could not locate karabiner source dir (chezmoi source-path err: %v)", err)
}

// runIn runs name+args in dir, streaming stdout/stderr to the terminal.
func runIn(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

// build runs the karabiner build script in the source dir. The source tree names
// it executable_build.sh (chezmoi prefix); the deployed tree names it build.sh.
func build(srcDir string) error {
	fmt.Println("\n→ Building…")
	script := "build.sh"
	if _, err := os.Stat(filepath.Join(srcDir, script)); err != nil {
		script = "executable_build.sh"
	}
	return runIn(srcDir, "bash", script)
}

// deploy runs chezmoi apply then goku. Never uses --force.
func deploy(srcDir string) error {
	fmt.Println("\n→ chezmoi apply…")
	if err := runIn(srcDir, "chezmoi", "apply"); err != nil {
		return err
	}
	fmt.Println("\n→ goku…")
	return runIn(srcDir, "goku")
}
