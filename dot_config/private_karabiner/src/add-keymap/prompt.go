package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

var stdin = bufio.NewReader(os.Stdin)

// readLine reads one trimmed line from stdin.
func readLine() string {
	s, _ := stdin.ReadString('\n')
	return strings.TrimSpace(s)
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

// askOptionalText prompts for a line that may be empty.
func askOptionalText(prompt string) string {
	fmt.Printf("%s ", prompt)
	return readLine()
}

// confirm asks a [y/N] question; default is No.
func confirm(prompt string) bool {
	fmt.Printf("%s [y/N] ", prompt)
	s := strings.ToLower(readLine())
	return s == "y" || s == "yes"
}
