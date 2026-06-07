package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "\nerror:", err)
		os.Exit(1)
	}
}

func run() error {
	srcDir, err := resolveSourceDir()
	if err != nil {
		return err
	}
	fmt.Println("add-keymap — karabiner source:", srcDir)

	layerID := askMenu("\nWhich layer?", layerOrder)
	layer := layerByID[layerID]

	if layerID == "hyper" {
		return runHyper(srcDir, layer)
	}
	return runFlat(srcDir, layer)
}

// runFlat handles app / workspace / l1 / l2 / l3.
func runFlat(srcDir string, layer Layer) error {
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	// Workspace: choose base vs shift section.
	section := layer.Section
	if layer.ID == "workspace" {
		if askMenu("\nBase or shift variant?", []string{"base (opt+key)", "shift (opt+shift+key)"}) == "shift (opt+shift+key)" {
			section = "workspace-shift"
		}
	}

	key := promptKey(text, section, layer.AllowUpper)

	label := askText("\nLabel (short, shown in help overlay):")

	var extra string
	switch layer.ID {
	case "app":
		extra = promptAppTarget()
	case "workspace":
		extra = askText("\nAerospace command (e.g. 'workspace 1'):")
	case "l1", "l2", "l3":
		extra = promptShortcutTarget()
	}

	line := buildFlatLine(key, label, extra)
	fmt.Printf("\nWill add to %s [%s]:\n  %s\n", layer.File, section, line)
	if !confirm("Proceed?") {
		return fmt.Errorf("cancelled")
	}

	updated, err := upsertFlatEntry(text, section, key, line)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
		return err
	}

	if err := build(srcDir); err != nil {
		return err
	}
	reportFlat(srcDir, layer, section, key, extra)
	return maybeDeploy(srcDir)
}

// runHyper handles the nested hyperkeys.yaml.
func runHyper(srcDir string, layer Layer) error {
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	key := promptHyperKey(text)
	existing := hyperModsForKey(text, key)

	var mod string
	for {
		mod = askMenu("\nModifier slot:", hyperModSlots)
		if !existing[mod] {
			break
		}
		if confirm(fmt.Sprintf("hyper+%s already maps %q — overwrite?", key, mod)) {
			break
		}
	}

	rawAction := askText("\nAction (goku key code, or comma-separated sequence):")
	if strings.HasPrefix(rawAction, "!") || strings.HasPrefix(rawAction, "#") {
		if err := validateGokuCombo(rawAction); err != nil {
			return err
		}
	}
	label := askText("Label (help overlay):")
	action := hyperAction(rawAction)

	fmt.Printf("\nWill add under hyper.%s:\n    %s: %s # %s\n", key, mod, action, label)
	if !confirm("Proceed?") {
		return fmt.Errorf("cancelled")
	}

	updated, err := upsertHyperEntry(text, key, mod, action, label)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
		return err
	}

	if err := build(srcDir); err != nil {
		return err
	}
	fmt.Printf("\n✓ Mapped: CapsLock + %s + %s → %s (%s)\n", mod, key, action, label)
	return maybeDeploy(srcDir)
}

// promptKey loops until a valid, non-colliding (or overwrite-confirmed) key.
func promptKey(text, section string, allowUpper bool) string {
	existing := sectionKeys(text, section)
	for {
		key := askText("\nKey to map:")
		if err := validateKey(key, allowUpper); err != nil {
			fmt.Println(" ", err)
			continue
		}
		if existing[key] {
			if confirm(fmt.Sprintf("%q is already mapped in this layer — overwrite?", key)) {
				return key
			}
			continue
		}
		return key
	}
}

// promptHyperKey validates a hyper key (no shift variants).
func promptHyperKey(text string) string {
	for {
		key := askText("\nKey to map (under CapsLock/hyper):")
		if err := validateKey(key, false); err != nil {
			fmt.Println(" ", err)
			continue
		}
		return key
	}
}

// promptAppTarget returns the YAML extra field for an app entry.
func promptAppTarget() string {
	if askMenu("\nTarget type:", []string{"App (open -a)", "Raw goku combo (!…)"}) == "Raw goku combo (!…)" {
		for {
			c := askText("Goku combo (e.g. !Cgrave_accent_and_tilde):")
			if err := validateGokuCombo(c); err != nil {
				fmt.Println(" ", err)
				continue
			}
			return c
		}
	}
	return askText("App name (as in /Applications, e.g. 'Microsoft Teams'):")
}

// promptShortcutTarget returns the YAML extra field for an l1/l2/l3 entry.
func promptShortcutTarget() string {
	choice := askMenu("\nMapping type:", []string{
		"F-key pool (auto-assign a combo to bind in Alfred/KM)",
		"Direct: open an app (open:App)",
		"Direct: raw goku combo (!…)",
	})
	switch {
	case strings.HasPrefix(choice, "F-key"):
		return "" // blank → pool
	case strings.HasPrefix(choice, "Direct: open"):
		return "open:" + askText("App name:")
	default:
		for {
			c := askText("Goku combo (e.g. !CSf13):")
			if err := validateGokuCombo(c); err != nil {
				fmt.Println(" ", err)
				continue
			}
			return c
		}
	}
}

// reportFlat prints the resulting mapping after a build.
func reportFlat(srcDir string, layer Layer, section, key, extra string) {
	switch layer.ID {
	case "l1", "l2", "l3":
		if strings.TrimSpace(extra) == "" {
			pool, err := readPool(filepath.Join(srcDir, "data", "fkey-pool.json"))
			if err == nil {
				if combo, ok := comboForKey(pool, layer.ID, key); ok {
					fmt.Printf("\n✓ Mapped: %s + %s → %s   (bind this in Alfred/KM)\n", layer.ID, key, combo)
					return
				}
			}
			fmt.Printf("\n✓ Added %s + %s to the F-key pool (see data/fkey-pool.json).\n", layer.ID, key)
		} else {
			fmt.Printf("\n✓ Mapped: %s + %s → %s\n", layer.ID, key, extra)
		}
	case "app":
		fmt.Printf("\n✓ Mapped: RightOpt + %s → %s\n", key, extra)
	case "workspace":
		mod := "LeftOpt"
		if section == "workspace-shift" {
			mod = "LeftOpt+Shift"
		}
		fmt.Printf("\n✓ Mapped: %s + %s → %s\n", mod, key, extra)
	}
}

// maybeDeploy offers to chezmoi apply + goku.
func maybeDeploy(srcDir string) error {
	if confirm("\nDeploy now (chezmoi apply && goku)?") {
		return deploy(srcDir)
	}
	fmt.Println("\nSkipped. To deploy later:\n  chezmoi apply && goku")
	return nil
}
