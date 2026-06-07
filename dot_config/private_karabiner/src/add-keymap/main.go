package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/huh"
)

func main() {
	opts, isCLI := parseCLI(os.Args[1:])
	if isCLI {
		if err := runCLI(opts); err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			os.Exit(1)
		}
		return
	}
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "\nerror:", err)
		os.Exit(1)
	}
}

func run() error {
	if err := ensureTTY(); err != nil {
		return err
	}
	srcDir, err := resolveSourceDir()
	if err != nil {
		return err
	}
	fmt.Println("add-keymap — karabiner source:", srcDir)

	layerID := layerOrder[0]
	if err := runForm(huh.NewGroup(
		huh.NewSelect[string]().
			Title("Which layer?").
			Options(huh.NewOptions(layerOrder...)...).
			Value(&layerID),
	)); err != nil {
		return err
	}
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

	section := layer.Section
	if layer.ID == "workspace" {
		variant := "base"
		if err := runForm(huh.NewGroup(
			huh.NewSelect[string]().
				Title("Base or shift variant?").
				Options(
					huh.NewOption("base (opt+key)", "base"),
					huh.NewOption("shift (opt+shift+key)", "shift"),
				).
				Value(&variant),
		)); err != nil {
			return err
		}
		if variant == "shift" {
			section = "workspace-shift"
		}
	}

	existing := sectionKeys(text, section)

	var key, label string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title("Key to map").
			Description(freeKeyHint(existing)).
			Validate(func(s string) error { return validateKey(strings.TrimSpace(s), layer.AllowUpper) }).
			Value(&key),
		huh.NewInput().
			Title("Label (short, shown in help overlay)").
			Validate(noPipe).
			Value(&label),
	)); err != nil {
		return err
	}
	key = strings.TrimSpace(key)
	label = strings.TrimSpace(label)

	if existing[key] {
		ok := false
		if err := runForm(huh.NewGroup(
			huh.NewConfirm().
				Title(fmt.Sprintf("%q is already mapped in this layer — overwrite?", key)).
				Value(&ok),
		)); err != nil {
			return err
		}
		if !ok {
			return fmt.Errorf("cancelled")
		}
	}

	extra, err := promptFlatTarget(layer)
	if err != nil {
		return err
	}

	line := buildFlatLine(key, label, extra)
	fmt.Printf("\nWill add to %s [%s]:\n  %s\n", layer.File, section, line)
	proceed := false
	if err := runForm(huh.NewGroup(
		huh.NewConfirm().Title("Proceed?").Value(&proceed),
	)); err != nil {
		return err
	}
	if !proceed {
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

// promptFlatTarget collects the YAML "extra" field per layer type.
func promptFlatTarget(layer Layer) (string, error) {
	switch layer.ID {
	case "workspace":
		var cmd string
		if err := runForm(huh.NewGroup(
			huh.NewInput().
				Title("Aerospace command (e.g. 'workspace 1')").
				Validate(noPipe).
				Value(&cmd),
		)); err != nil {
			return "", err
		}
		return strings.TrimSpace(cmd), nil

	case "app":
		kind := "app"
		if err := runForm(huh.NewGroup(
			huh.NewSelect[string]().
				Title("Target type").
				Options(
					huh.NewOption("App (open -a)", "app"),
					huh.NewOption("Raw goku combo (!…)", "combo"),
				).
				Value(&kind),
		)); err != nil {
			return "", err
		}
		if kind == "combo" {
			return promptCombo("Goku combo (e.g. !Cgrave_accent_and_tilde)")
		}
		var app string
		if err := runForm(huh.NewGroup(
			huh.NewInput().
				Title("App name (as in /Applications, e.g. 'Microsoft Teams')").
				Validate(noPipe).
				Value(&app),
		)); err != nil {
			return "", err
		}
		return strings.TrimSpace(app), nil

	default: // l1, l2, l3
		kind := "pool"
		if err := runForm(huh.NewGroup(
			huh.NewSelect[string]().
				Title("Mapping type").
				Options(
					huh.NewOption("F-key pool (auto-assign a combo to bind in Alfred/KM)", "pool"),
					huh.NewOption("Direct: open an app (open:App)", "open"),
					huh.NewOption("Direct: raw goku combo (!…)", "combo"),
				).
				Value(&kind),
		)); err != nil {
			return "", err
		}
		switch kind {
		case "pool":
			return "", nil
		case "open":
			var app string
			if err := runForm(huh.NewGroup(
				huh.NewInput().Title("App name").Validate(noPipe).Value(&app),
			)); err != nil {
				return "", err
			}
			return "open:" + strings.TrimSpace(app), nil
		default:
			return promptCombo("Goku combo (e.g. !CSf13)")
		}
	}
}

// promptCombo asks for a goku combo and validates it.
func promptCombo(title string) (string, error) {
	var c string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title(title).
			Validate(func(s string) error { return validateGokuCombo(strings.TrimSpace(s)) }).
			Value(&c),
	)); err != nil {
		return "", err
	}
	return strings.TrimSpace(c), nil
}

// noPipe rejects empty values and values containing '|' (the YAML field delimiter).
func noPipe(s string) error {
	if strings.TrimSpace(s) == "" {
		return fmt.Errorf("value cannot be empty")
	}
	if strings.Contains(s, "|") {
		return fmt.Errorf("value cannot contain '|'")
	}
	return nil
}

// runHyper handles the nested hyperkeys.yaml.
func runHyper(srcDir string, layer Layer) error {
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	var key string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title("Key to map (under CapsLock/hyper)").
			Validate(func(s string) error { return validateKey(strings.TrimSpace(s), false) }).
			Value(&key),
	)); err != nil {
		return err
	}
	key = strings.TrimSpace(key)
	existing := hyperModsForKey(text, key)

	mod := hyperModSlots[0]
	if err := runForm(huh.NewGroup(
		huh.NewSelect[string]().
			Title("Modifier slot").
			Options(huh.NewOptions(hyperModSlots...)...).
			Value(&mod),
	)); err != nil {
		return err
	}
	if existing[mod] {
		ok := false
		if err := runForm(huh.NewGroup(
			huh.NewConfirm().
				Title(fmt.Sprintf("hyper+%s already maps %q — overwrite?", key, mod)).
				Value(&ok),
		)); err != nil {
			return err
		}
		if !ok {
			return fmt.Errorf("cancelled")
		}
	}

	var rawAction, label string
	if err := runForm(huh.NewGroup(
		huh.NewInput().
			Title("Action (goku key code, or comma-separated sequence)").
			Validate(func(s string) error {
				s = strings.TrimSpace(s)
				if s == "" {
					return fmt.Errorf("action cannot be empty")
				}
				if strings.HasPrefix(s, "!") || strings.HasPrefix(s, "#") {
					return validateGokuCombo(s)
				}
				return nil
			}).
			Value(&rawAction),
		huh.NewInput().
			Title("Label (help overlay)").
			Validate(noPipe).
			Value(&label),
	)); err != nil {
		return err
	}
	rawAction = strings.TrimSpace(rawAction)
	label = strings.TrimSpace(label)
	action := hyperAction(rawAction)

	fmt.Printf("\nWill add under hyper.%s:\n    %s: %s # %s\n", key, mod, action, label)
	proceed := false
	if err := runForm(huh.NewGroup(
		huh.NewConfirm().Title("Proceed?").Value(&proceed),
	)); err != nil {
		return err
	}
	if !proceed {
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
	deployNow := false
	if err := runForm(huh.NewGroup(
		huh.NewConfirm().Title("Deploy now (chezmoi apply && goku)?").Value(&deployNow),
	)); err != nil {
		return err
	}
	if deployNow {
		return deploy(srcDir)
	}
	fmt.Println("\nSkipped. To deploy later:\n  chezmoi apply && goku")
	return nil
}
