package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const version = "0.1.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	switch os.Args[1] {
	case "version", "--version", "-v":
		fmt.Println(version)
	case "help", "--help", "-h":
		usage()
	case "k8s":
		if err := runK8s(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", os.Args[1])
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Println(`opsro - read-only operations CLI

Usage:
  opsro version
  opsro k8s [--context NAME] [--namespace NS] <get|describe|logs|events|top> [args...]

Examples:
  opsro k8s --context prod get pods -A
  opsro k8s --context prod describe deployment api -n prod
  opsro k8s --context prod logs deployment/api -n prod --since=10m
  opsro k8s --context prod events -n prod
  opsro k8s --context prod top pods -n prod
`)
}

func runK8s(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("missing k8s subcommand")
	}

	context := ""
	namespace := ""
	rest := make([]string, 0, len(args))

	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "--context":
			if i+1 >= len(args) {
				return fmt.Errorf("--context requires a value")
			}
			context = args[i+1]
			i++
		case "--namespace", "-n":
			if i+1 >= len(args) {
				return fmt.Errorf("%s requires a value", a)
			}
			namespace = args[i+1]
			i++
		default:
			rest = append(rest, a)
		}
	}

	if len(rest) == 0 {
		return fmt.Errorf("missing k8s verb")
	}

	verb := rest[0]
	allowed := map[string]bool{
		"get":      true,
		"describe": true,
		"logs":     true,
		"events":   true,
		"top":      true,
	}
	if !allowed[verb] {
		return fmt.Errorf("verb %q is not allowed; only get, describe, logs, events, and top are supported", verb)
	}

	kubectlArgs := make([]string, 0, len(rest)+4)
	if context != "" {
		kubectlArgs = append(kubectlArgs, "--context", context)
	}

	switch verb {
	case "events":
		kubectlArgs = append(kubectlArgs, "get", "events")
		kubectlArgs = append(kubectlArgs, rest[1:]...)
	case "get", "describe", "logs", "top":
		kubectlArgs = append(kubectlArgs, verb)
		kubectlArgs = append(kubectlArgs, rest[1:]...)
	}

	if namespace != "" && !containsNamespaceFlag(rest[1:]) {
		kubectlArgs = append(kubectlArgs, "-n", namespace)
	}

	cmd := exec.Command(kubectlBinary(), kubectlArgs...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

func kubectlBinary() string {
	if v := strings.TrimSpace(os.Getenv("OPSRO_KUBECTL")); v != "" {
		return v
	}
	return "kubectl"
}

func containsNamespaceFlag(args []string) bool {
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "-n" || a == "--namespace" || strings.HasPrefix(a, "--namespace=") {
			return true
		}
	}
	return false
}
