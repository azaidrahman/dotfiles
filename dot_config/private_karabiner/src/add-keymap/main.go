package main

import (
	"fmt"
	"os"
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
