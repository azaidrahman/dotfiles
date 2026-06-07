package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// resolveSourceDir returns the chezmoi *source* path of the karabiner config dir.
// Primary: `chezmoi source-path ~/.config/karabiner`. Fallback: two levels up
// from the running binary (…/karabiner/scripts/add-keymap -> …/karabiner).
func resolveSourceDir() (string, error) {
	home, _ := os.UserHomeDir()
	target := filepath.Join(home, ".config", "karabiner")
	out, err := exec.Command("chezmoi", "source-path", target).Output()
	if err == nil {
		dir := strings.TrimSpace(string(out))
		if dir != "" {
			if _, statErr := os.Stat(filepath.Join(dir, "build.sh")); statErr == nil {
				return dir, nil
			}
		}
	}
	exe, exeErr := os.Executable()
	if exeErr == nil {
		cand := filepath.Dir(filepath.Dir(exe)) // scripts/ -> karabiner/
		if _, statErr := os.Stat(filepath.Join(cand, "build.sh")); statErr == nil {
			return cand, nil
		}
	}
	return "", fmt.Errorf("could not locate karabiner source dir (chezmoi source-path failed: %v)", err)
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

// build runs ./build.sh in the source dir.
func build(srcDir string) error {
	fmt.Println("\n→ Building (./build.sh)…")
	return runIn(srcDir, "./build.sh")
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
