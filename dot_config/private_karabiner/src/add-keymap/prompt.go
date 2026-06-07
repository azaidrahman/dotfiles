package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

var stdin = bufio.NewReader(os.Stdin)

// readLine reads one trimmed line from stdin. On end-of-input (e.g. piped input
// runs out) it aborts rather than returning "" forever, which would make the
// re-prompting loops in askMenu/askText spin endlessly. For unattended use,
// prefer the non-interactive flag mode (see -h).
func readLine() string {
	s, err := stdin.ReadString('\n')
	line := strings.TrimSpace(s)
	if err == io.EOF && line == "" {
		fmt.Fprintln(os.Stderr, "\nadd-keymap: unexpected end of input — for unattended use, run with flags (see -h)")
		os.Exit(1)
	}
	return line
}

// askMenu prints a numbered menu and returns the chosen item (loops until valid).
func askMenu(title string, options []string) string {
	for {
		fmt.Println(title)
		for i, o := range options {
			fmt.Printf("  %d) %s\n", i+1, o)
		}
		fmt.Print("> ")
		n, err := strconv.Atoi(readLine())
		if err == nil && n >= 1 && n <= len(options) {
			return options[n-1]
		}
		fmt.Println("Please enter a number from the list.")
	}
}

// askText prompts for a non-empty line (loops until non-empty).
func askText(prompt string) string {
	for {
		fmt.Printf("%s ", prompt)
		s := readLine()
		if s != "" {
			return s
		}
		fmt.Println("Value cannot be empty.")
	}
}

// askTextNoPipe prompts for non-empty text that contains no '|' — used for
// fields written into the pipe-delimited "key | label | extra" YAML format,
// where a '|' would silently corrupt parsing.
func askTextNoPipe(prompt string) string {
	for {
		s := askText(prompt)
		if !strings.Contains(s, "|") {
			return s
		}
		fmt.Println("  value cannot contain '|'")
	}
}

// confirm asks a [y/N] question; default is No.
func confirm(prompt string) bool {
	fmt.Printf("%s [y/N] ", prompt)
	s := strings.ToLower(readLine())
	return s == "y" || s == "yes"
}
