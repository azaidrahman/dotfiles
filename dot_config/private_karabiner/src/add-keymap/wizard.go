package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/huh"
)

// wizard holds every answer collected by the single interactive form. The whole
// flow lives in ONE huh.Form so huh's native back navigation (shift+tab) works
// across every screen. Groups are shown/hidden per-layer via WithHideFunc, and
// fields that depend on earlier answers use *Func builders bound to w.
//
// Fields are EXPORTED on purpose: huh hashes the bindings value (via
// hashstructure, which only sees exported fields) to decide when to recompute a
// dynamic Title/Description, so binding to w makes those recompute on any change.
type wizard struct {
	Layer     string // layer id (app/workspace/l1/l2/l3/hyper)
	WSVariant string // workspace: "base" | "shift"
	Key       string // flat key
	Label     string // flat label
	AppTarget string // app layer target kind: "app" | "combo"
	LTarget   string // l1/l2/l3 mapping kind: "pool" | "open" | "combo"
	AppName   string // app-name target (app→App, l*→open:App)
	Combo     string // raw goku combo target
	WSCmd     string // aerospace command (workspace)
	HyperKey  string
	HyperMod  string
	HyperAct  string
	HyperLbl  string
	Overwrite bool // overwrite confirm (flat or hyper)
	Proceed   bool
	Deploy    bool
}

func (w *wizard) isFlat() bool { return w.Layer != "hyper" }
func (w *wizard) isL() bool {
	return w.Layer == "l1" || w.Layer == "l2" || w.Layer == "l3"
}

// section returns the YAML section for the chosen flat layer (workspace splits
// into base/shift). Meaningless for hyper.
func (w *wizard) section() string {
	if w.Layer == "workspace" && w.WSVariant == "shift" {
		return "workspace-shift"
	}
	return layerByID[w.Layer].Section
}

// flatExtra renders the YAML "extra" field for the chosen flat target.
func (w *wizard) flatExtra() string {
	switch {
	case w.Layer == "workspace":
		return strings.TrimSpace(w.WSCmd)
	case w.Layer == "app":
		if w.AppTarget == "combo" {
			return strings.TrimSpace(w.Combo)
		}
		return strings.TrimSpace(w.AppName)
	default: // l1, l2, l3
		switch w.LTarget {
		case "open":
			return "open:" + strings.TrimSpace(w.AppName)
		case "combo":
			return strings.TrimSpace(w.Combo)
		default: // pool
			return ""
		}
	}
}

// preview is the human-readable summary shown on the review screen.
func (w *wizard) preview() string {
	if w.Layer == "hyper" {
		return fmt.Sprintf("hyper.%s\n  %s: %s  # %s",
			strings.TrimSpace(w.HyperKey), w.HyperMod,
			hyperAction(strings.TrimSpace(w.HyperAct)), strings.TrimSpace(w.HyperLbl))
	}
	layer := layerByID[w.Layer]
	line := buildFlatLine(strings.TrimSpace(w.Key), strings.TrimSpace(w.Label), w.flatExtra())
	return fmt.Sprintf("%s [%s]\n  %s", layer.File, w.section(), line)
}

// run drives the interactive wizard: one multi-group form (with back nav),
// then the file edit / build / deploy based on the collected answers.
func run() error {
	if err := ensureTTY(); err != nil {
		return err
	}
	srcDir, err := resolveSourceDir()
	if err != nil {
		return err
	}
	fmt.Println("add-keymap — karabiner source:", srcDir)

	// Pre-read every layer file once so the live hint/collision funcs below can
	// run during rendering without hitting the disk or erroring mid-form.
	cache := map[string]string{}
	for _, id := range layerOrder {
		file := layerByID[id].File
		if _, ok := cache[file]; ok {
			continue
		}
		b, readErr := os.ReadFile(filepath.Join(srcDir, file))
		if readErr != nil {
			return readErr
		}
		cache[file] = string(b)
	}

	w := &wizard{
		Layer:     layerOrder[0],
		WSVariant: "base",
		AppTarget: "app",
		LTarget:   "pool",
		HyperMod:  hyperModSlots[0],
	}

	// Live helpers (read-only) used by the form's dynamic fields.
	flatExisting := func() map[string]bool {
		return sectionKeys(cache[layerByID[w.Layer].File], w.section())
	}
	flatCollision := func() bool {
		k := strings.TrimSpace(w.Key)
		return k != "" && flatExisting()[k]
	}
	hyperCollision := func() bool {
		k := strings.TrimSpace(w.HyperKey)
		return k != "" && hyperModsForKey(cache[layerByID["hyper"].File], k)[w.HyperMod]
	}
	needAppName := func() bool {
		return (w.Layer == "app" && w.AppTarget == "app") || (w.isL() && w.LTarget == "open")
	}
	needCombo := func() bool {
		return (w.Layer == "app" && w.AppTarget == "combo") || (w.isL() && w.LTarget == "combo")
	}

	groups := []*huh.Group{
		// 1. Layer.
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Which layer?").
				Description("A layer is a hold-modifier mode; the trigger is shown beside each.").
				Options(layerOptions()...).
				Value(&w.Layer),
		),
		// 2. Workspace variant.
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Base or shift variant?").
				Options(
					huh.NewOption("base (opt+key)", "base"),
					huh.NewOption("shift (opt+shift+key)", "shift"),
				).
				Value(&w.WSVariant),
		).WithHideFunc(func() bool { return w.Layer != "workspace" }),
		// 3. Flat key + label.
		huh.NewGroup(
			huh.NewInput().
				Title("Key to map").
				DescriptionFunc(func() string { return freeKeyHint(flatExisting()) }, w).
				Validate(func(s string) error {
					return validateKey(strings.TrimSpace(s), layerByID[w.Layer].AllowUpper)
				}).
				Value(&w.Key),
			huh.NewInput().
				Title("Label (short, shown in help overlay)").
				Validate(noPipe).
				Value(&w.Label),
		).WithHideFunc(func() bool { return !w.isFlat() }),
		// 4. Flat overwrite confirm (only on collision).
		huh.NewGroup(
			huh.NewConfirm().
				TitleFunc(func() string {
					return fmt.Sprintf("%q is already mapped in this layer — overwrite?", strings.TrimSpace(w.Key))
				}, w).
				Value(&w.Overwrite),
		).WithHideFunc(func() bool { return !(w.isFlat() && flatCollision()) }),
		// 5. App target type.
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Target type").
				Options(
					huh.NewOption("App (open -a)", "app"),
					huh.NewOption("Raw goku combo (!…)", "combo"),
				).
				Value(&w.AppTarget),
		).WithHideFunc(func() bool { return w.Layer != "app" }),
		// 6. l1/l2/l3 mapping type.
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Mapping type").
				Options(
					huh.NewOption("F-key pool (auto-assign a combo to bind in Alfred/KM)", "pool"),
					huh.NewOption("Direct: open an app (open:App)", "open"),
					huh.NewOption("Direct: raw goku combo (!…)", "combo"),
				).
				Value(&w.LTarget),
		).WithHideFunc(func() bool { return !w.isL() }),
		// 7. App name (app→App, l*→open:App).
		huh.NewGroup(
			huh.NewInput().
				Title("App name (as in /Applications, e.g. 'Microsoft Teams')").
				Validate(noPipe).
				Value(&w.AppName),
		).WithHideFunc(func() bool { return !needAppName() }),
		// 8. Raw goku combo (app or l*).
		huh.NewGroup(
			huh.NewInput().
				Title("Goku combo (e.g. !Cgrave_accent_and_tilde)").
				Validate(func(s string) error { return validateGokuCombo(strings.TrimSpace(s)) }).
				Value(&w.Combo),
		).WithHideFunc(func() bool { return !needCombo() }),
		// 9. Workspace aerospace command.
		huh.NewGroup(
			huh.NewInput().
				Title("Aerospace command (e.g. 'workspace 1')").
				Validate(noPipe).
				Value(&w.WSCmd),
		).WithHideFunc(func() bool { return w.Layer != "workspace" }),
		// 10. Hyper key.
		huh.NewGroup(
			huh.NewInput().
				Title("Key to map (under CapsLock/hyper)").
				Validate(func(s string) error { return validateKey(strings.TrimSpace(s), false) }).
				Value(&w.HyperKey),
		).WithHideFunc(func() bool { return w.Layer != "hyper" }),
		// 11. Hyper modifier slot.
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Modifier slot").
				Options(huh.NewOptions(hyperModSlots...)...).
				Value(&w.HyperMod),
		).WithHideFunc(func() bool { return w.Layer != "hyper" }),
		// 12. Hyper overwrite confirm (only on collision).
		huh.NewGroup(
			huh.NewConfirm().
				TitleFunc(func() string {
					return fmt.Sprintf("hyper+%s already maps %q — overwrite?", strings.TrimSpace(w.HyperKey), w.HyperMod)
				}, w).
				Value(&w.Overwrite),
		).WithHideFunc(func() bool { return !(w.Layer == "hyper" && hyperCollision()) }),
		// 13. Hyper action + label.
		huh.NewGroup(
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
				Value(&w.HyperAct),
			huh.NewInput().
				Title("Label (help overlay)").
				Validate(noPipe).
				Value(&w.HyperLbl),
		).WithHideFunc(func() bool { return w.Layer != "hyper" }),
		// 14. Review + proceed.
		huh.NewGroup(
			huh.NewNote().
				Title("Review").
				DescriptionFunc(func() string { return w.preview() }, w),
			huh.NewConfirm().
				Title("Proceed?").
				Value(&w.Proceed),
		),
		// 15. Deploy.
		huh.NewGroup(
			huh.NewConfirm().
				Title("Deploy now (chezmoi apply && goku)?").
				Value(&w.Deploy),
		),
	}

	if err := runForm(groups...); err != nil {
		return err
	}
	if !w.Proceed {
		return fmt.Errorf("cancelled")
	}

	if w.isFlat() {
		return applyFlat(srcDir, w)
	}
	return applyHyper(srcDir, w)
}

// applyFlat writes the flat-layer entry, rebuilds, reports, and offers deploy.
func applyFlat(srcDir string, w *wizard) error {
	layer := layerByID[w.Layer]
	section := w.section()
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	key := strings.TrimSpace(w.Key)
	if sectionKeys(text, section)[key] && !w.Overwrite {
		return fmt.Errorf("cancelled — %q already mapped and overwrite not confirmed", key)
	}

	extra := w.flatExtra()
	line := buildFlatLine(key, strings.TrimSpace(w.Label), extra)
	fmt.Printf("\nWill add to %s [%s]:\n  %s\n", layer.File, section, line)

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
	return finishDeploy(srcDir, w)
}

// applyHyper writes the hyper entry, rebuilds, reports, and offers deploy.
func applyHyper(srcDir string, w *wizard) error {
	layer := layerByID["hyper"]
	path := filepath.Join(srcDir, layer.File)
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(b)

	key := strings.TrimSpace(w.HyperKey)
	if hyperModsForKey(text, key)[w.HyperMod] && !w.Overwrite {
		return fmt.Errorf("cancelled — hyper+%s %q already mapped and overwrite not confirmed", key, w.HyperMod)
	}

	label := strings.TrimSpace(w.HyperLbl)
	action := hyperAction(strings.TrimSpace(w.HyperAct))
	fmt.Printf("\nWill add under hyper.%s:\n    %s: %s # %s\n", key, w.HyperMod, action, label)

	updated, err := upsertHyperEntry(text, key, w.HyperMod, action, label)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(updated), 0o644); err != nil {
		return err
	}
	if err := build(srcDir); err != nil {
		return err
	}
	fmt.Printf("\n✓ Mapped: CapsLock + %s + %s → %s (%s)\n", w.HyperMod, key, action, label)
	return finishDeploy(srcDir, w)
}

// finishDeploy runs chezmoi apply + goku, or prints the manual hint.
func finishDeploy(srcDir string, w *wizard) error {
	if w.Deploy {
		return deploy(srcDir)
	}
	fmt.Println("\nSkipped. To deploy later:\n  chezmoi apply && goku")
	return nil
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
