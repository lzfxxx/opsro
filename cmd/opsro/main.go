package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

const version = "0.2.0"

type config struct {
	Hosts map[string]hostConfig `json:"hosts"`
}

type hostConfig struct {
	Address string `json:"address"`
	User    string `json:"user"`
	Port    int    `json:"port"`
}

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
	case "host":
		if err := runHost(os.Args[2:]); err != nil {
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
	fmt.Print(`opsro - read-only operations CLI

Usage:
  opsro version
  opsro k8s [--context NAME] [--namespace NS] <get|describe|logs|events|top> [args...]
  opsro host [--config PATH] <status|logs|run> <host> [args...]

Examples:
  opsro k8s --context prod get pods -A
  opsro k8s --context prod describe deployment api -n prod
  opsro k8s --context prod logs deployment/api -n prod --since=10m
  opsro k8s --context prod events -n prod
  opsro k8s --context prod top pods -n prod

  opsro host status web-01
  opsro host logs web-01 nginx --since=10m --tail=200
  opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
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

func runHost(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("missing host subcommand")
	}

	configPath := ""
	rest := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "--config":
			if i+1 >= len(args) {
				return fmt.Errorf("--config requires a value")
			}
			configPath = args[i+1]
			i++
		default:
			rest = append(rest, a)
		}
	}

	if len(rest) < 2 {
		return fmt.Errorf("usage: opsro host [--config PATH] <status|logs|run> <host> [args...]")
	}

	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}

	subcommand := rest[0]
	hostName := rest[1]
	host, ok := cfg.Hosts[hostName]
	if !ok {
		return fmt.Errorf("host %q not found in config", hostName)
	}

	switch subcommand {
	case "status":
		if len(rest) != 2 {
			return fmt.Errorf("usage: opsro host status <host>")
		}
		return runSSH(host, []string{"opsro-broker", "status"})
	case "logs":
		if len(rest) < 3 {
			return fmt.Errorf("usage: opsro host logs <host> <service> [--since=10m] [--tail=200]")
		}
		service := rest[2]
		if !isSafeToken(service) {
			return fmt.Errorf("unsafe service name: %q", service)
		}
		sshArgs := []string{"opsro-broker", "logs", service}
		for _, a := range rest[3:] {
			if !strings.HasPrefix(a, "--since=") && !strings.HasPrefix(a, "--tail=") {
				return fmt.Errorf("unsupported logs arg %q; only --since=... and --tail=... are allowed", a)
			}
			if !isSafeToken(a) {
				return fmt.Errorf("unsafe logs arg: %q", a)
			}
			sshArgs = append(sshArgs, a)
		}
		return runSSH(host, sshArgs)
	case "run":
		if len(rest) < 4 {
			return fmt.Errorf("usage: opsro host run <host> -- <readonly command args...>")
		}
		runArgs := rest[2:]
		if runArgs[0] == "--" {
			runArgs = runArgs[1:]
		}
		if len(runArgs) == 0 {
			return fmt.Errorf("missing readonly command after --")
		}
		for _, a := range runArgs {
			if !isSafeToken(a) {
				return fmt.Errorf("unsafe host arg: %q", a)
			}
		}
		return runSSH(host, append([]string{"opsro-broker", "run"}, runArgs...))
	default:
		return fmt.Errorf("unsupported host subcommand %q; only status, logs, and run are supported", subcommand)
	}
}

func loadConfig(explicit string) (*config, error) {
	path := explicit
	if path == "" {
		path = strings.TrimSpace(os.Getenv("OPSRO_CONFIG"))
	}
	if path == "" {
		if _, err := os.Stat("opsro.json"); err == nil {
			path = "opsro.json"
		} else if home, err := os.UserHomeDir(); err == nil {
			path = filepath.Join(home, ".config", "opsro", "config.json")
		}
	}
	if path == "" {
		return nil, fmt.Errorf("no config path found")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}

	var cfg config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}
	if cfg.Hosts == nil {
		cfg.Hosts = map[string]hostConfig{}
	}
	return &cfg, nil
}

func runSSH(host hostConfig, remoteArgs []string) error {
	if host.Address == "" {
		return fmt.Errorf("host config is missing address")
	}
	user := host.User
	if user == "" {
		user = "opsro"
	}
	port := host.Port
	if port == 0 {
		port = 22
	}

	sshArgs := []string{"-p", strconv.Itoa(port), fmt.Sprintf("%s@%s", user, host.Address)}
	sshArgs = append(sshArgs, remoteArgs...)
	cmd := exec.Command(sshBinary(), sshArgs...)
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

func sshBinary() string {
	if v := strings.TrimSpace(os.Getenv("OPSRO_SSH")); v != "" {
		return v
	}
	return "ssh"
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

func isSafeToken(s string) bool {
	if strings.TrimSpace(s) == "" {
		return false
	}
	if strings.ContainsAny(s, " \n\r\t;|&><`$(){}[]\\\"") {
		return false
	}
	return true
}
