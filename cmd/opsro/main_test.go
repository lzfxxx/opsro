package main

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestContainsNamespaceFlag(t *testing.T) {
	cases := []struct {
		name string
		args []string
		want bool
	}{
		{name: "short", args: []string{"pods", "-n", "prod"}, want: true},
		{name: "long", args: []string{"pods", "--namespace", "prod"}, want: true},
		{name: "equals", args: []string{"pods", "--namespace=prod"}, want: true},
		{name: "none", args: []string{"pods", "-A"}, want: false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := containsNamespaceFlag(tc.args); got != tc.want {
				t.Fatalf("containsNamespaceFlag(%v) = %v, want %v", tc.args, got, tc.want)
			}
		})
	}
}

func TestIsSafeToken(t *testing.T) {
	good := []string{"nginx", "--since=10m", "/var/log/nginx/access.log", "deployment/api"}
	for _, token := range good {
		if !isSafeToken(token) {
			t.Fatalf("expected safe token: %q", token)
		}
	}

	bad := []string{"", "bash -c", "foo;bar", "$(id)", "a|b", "x>y", "\"quoted\""}
	for _, token := range bad {
		if isSafeToken(token) {
			t.Fatalf("expected unsafe token: %q", token)
		}
	}
}

func TestKubectlBinary(t *testing.T) {
	t.Setenv("OPSRO_KUBECTL", "/tmp/fake-kubectl")
	if got := kubectlBinary(); got != "/tmp/fake-kubectl" {
		t.Fatalf("kubectlBinary() = %q, want override", got)
	}
}

func TestSSHBinary(t *testing.T) {
	t.Setenv("OPSRO_SSH", "/tmp/fake-ssh")
	if got := sshBinary(); got != "/tmp/fake-ssh" {
		t.Fatalf("sshBinary() = %q, want override", got)
	}
}

func TestRunK8sValidatesInput(t *testing.T) {
	cases := []struct {
		name string
		args []string
		want string
	}{
		{name: "missing", args: nil, want: "missing k8s subcommand"},
		{name: "missing context value", args: []string{"--context"}, want: "--context requires a value"},
		{name: "missing namespace value", args: []string{"get", "pods", "-n"}, want: "-n requires a value"},
		{name: "missing verb", args: []string{"--context", "prod"}, want: "missing k8s verb"},
		{name: "unsupported verb", args: []string{"delete", "pods"}, want: "is not allowed"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := runK8s(tc.args)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("runK8s(%v) error = %v, want substring %q", tc.args, err, tc.want)
			}
		})
	}
}

func TestRunK8sBuildsKubectlArgs(t *testing.T) {
	captureFile := filepath.Join(t.TempDir(), "kubectl-args.txt")
	fakeKubectl := writeCaptureScript(t, "kubectl", captureFile)
	t.Setenv("OPSRO_KUBECTL", fakeKubectl)

	if err := runK8s([]string{"--context", "prod", "--namespace", "app", "get", "pods", "-A"}); err != nil {
		t.Fatalf("runK8s returned error: %v", err)
	}

	got := readLines(t, captureFile)
	want := []string{"--context", "prod", "get", "pods", "-A", "-n", "app"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("kubectl args = %v, want %v", got, want)
	}
}

func TestRunK8sHandlesEventsAndExistingNamespace(t *testing.T) {
	captureFile := filepath.Join(t.TempDir(), "kubectl-events.txt")
	fakeKubectl := writeCaptureScript(t, "kubectl", captureFile)
	t.Setenv("OPSRO_KUBECTL", fakeKubectl)

	if err := runK8s([]string{"-n", "ops", "events", "--namespace=prod"}); err != nil {
		t.Fatalf("runK8s returned error: %v", err)
	}

	got := readLines(t, captureFile)
	want := []string{"get", "events", "--namespace=prod"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("kubectl args = %v, want %v", got, want)
	}
}

func TestLoadConfigSources(t *testing.T) {
	t.Run("explicit path", func(t *testing.T) {
		configPath := writeConfigFile(t, filepath.Join(t.TempDir(), "opsro.json"))
		cfg, err := loadConfig(configPath)
		if err != nil {
			t.Fatalf("loadConfig returned error: %v", err)
		}
		if cfg.Hosts["web-01"].Address != "10.0.1.12" {
			t.Fatalf("unexpected config: %+v", cfg.Hosts)
		}
	})

	t.Run("env path", func(t *testing.T) {
		configPath := writeConfigFile(t, filepath.Join(t.TempDir(), "env-config.json"))
		t.Setenv("OPSRO_CONFIG", configPath)
		cfg, err := loadConfig("")
		if err != nil {
			t.Fatalf("loadConfig returned error: %v", err)
		}
		if cfg.Hosts["web-01"].User != "opsro" {
			t.Fatalf("unexpected config: %+v", cfg.Hosts)
		}
	})

	t.Run("cwd fallback", func(t *testing.T) {
		dir := t.TempDir()
		writeConfigFile(t, filepath.Join(dir, "opsro.json"))
		oldWD, err := os.Getwd()
		if err != nil {
			t.Fatalf("Getwd: %v", err)
		}
		if err := os.Chdir(dir); err != nil {
			t.Fatalf("Chdir: %v", err)
		}
		defer func() { _ = os.Chdir(oldWD) }()

		cfg, err := loadConfig("")
		if err != nil {
			t.Fatalf("loadConfig returned error: %v", err)
		}
		if _, ok := cfg.Hosts["web-01"]; !ok {
			t.Fatalf("expected host from cwd config")
		}
	})
}

func TestLoadConfigErrors(t *testing.T) {
	if _, err := loadConfig(filepath.Join(t.TempDir(), "missing.json")); err == nil || !strings.Contains(err.Error(), "read config") {
		t.Fatalf("expected read config error, got %v", err)
	}

	badPath := filepath.Join(t.TempDir(), "bad.json")
	if err := os.WriteFile(badPath, []byte("{"), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	if _, err := loadConfig(badPath); err == nil || !strings.Contains(err.Error(), "parse config") {
		t.Fatalf("expected parse config error, got %v", err)
	}
}

func TestRunHostValidatesInput(t *testing.T) {
	configPath := writeConfigFile(t, filepath.Join(t.TempDir(), "opsro.json"))

	cases := []struct {
		name string
		args []string
		want string
	}{
		{name: "missing subcommand", args: nil, want: "missing host subcommand"},
		{name: "missing config value", args: []string{"--config"}, want: "--config requires a value"},
		{name: "missing host name", args: []string{"status"}, want: "usage: opsro host"},
		{name: "unknown host", args: []string{"--config", configPath, "status", "missing"}, want: "not found in config"},
		{name: "bad logs arg", args: []string{"--config", configPath, "logs", "web-01", "nginx", "--tail", "100"}, want: "unsupported logs arg"},
		{name: "unsafe service", args: []string{"--config", configPath, "logs", "web-01", "nginx;id"}, want: "unsafe service name"},
		{name: "unsafe run arg", args: []string{"--config", configPath, "run", "web-01", "--", "echo", "hello world"}, want: "unsafe host arg"},
		{name: "unsupported subcommand", args: []string{"--config", configPath, "exec", "web-01"}, want: "unsupported host subcommand"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := runHost(tc.args)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("runHost(%v) error = %v, want substring %q", tc.args, err, tc.want)
			}
		})
	}
}

func TestRunHostBuildsSSHArgs(t *testing.T) {
	configPath := writeConfigFile(t, filepath.Join(t.TempDir(), "opsro.json"))
	captureFile := filepath.Join(t.TempDir(), "ssh-args.txt")
	fakeSSH := writeCaptureScript(t, "ssh", captureFile)
	t.Setenv("OPSRO_SSH", fakeSSH)

	if err := runHost([]string{"--config", configPath, "status", "web-01"}); err != nil {
		t.Fatalf("runHost status returned error: %v", err)
	}
	got := readLines(t, captureFile)
	want := []string{"-p", "2200", "opsro@10.0.1.12", "opsro-broker", "status"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ssh args = %v, want %v", got, want)
	}

	if err := runHost([]string{"--config", configPath, "logs", "web-01", "nginx", "--since=15m", "--tail=50"}); err != nil {
		t.Fatalf("runHost logs returned error: %v", err)
	}
	got = readLines(t, captureFile)
	want = []string{"-p", "2200", "opsro@10.0.1.12", "opsro-broker", "logs", "nginx", "--since=15m", "--tail=50"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ssh args = %v, want %v", got, want)
	}

	if err := runHost([]string{"--config", configPath, "run", "web-01", "--", "journalctl", "-u", "nginx", "--since=10m"}); err != nil {
		t.Fatalf("runHost run returned error: %v", err)
	}
	got = readLines(t, captureFile)
	want = []string{"-p", "2200", "opsro@10.0.1.12", "opsro-broker", "run", "journalctl", "-u", "nginx", "--since=10m"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ssh args = %v, want %v", got, want)
	}
}

func TestRunSSHDefaults(t *testing.T) {
	captureFile := filepath.Join(t.TempDir(), "ssh-defaults.txt")
	fakeSSH := writeCaptureScript(t, "ssh", captureFile)
	t.Setenv("OPSRO_SSH", fakeSSH)

	host := hostConfig{Address: "10.0.1.20"}
	if err := runSSH(host, []string{"opsro-broker", "status"}); err != nil {
		t.Fatalf("runSSH returned error: %v", err)
	}
	got := readLines(t, captureFile)
	want := []string{"-p", "22", "opsro@10.0.1.20", "opsro-broker", "status"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ssh args = %v, want %v", got, want)
	}
}

func TestRunSSHErrorsOnMissingAddress(t *testing.T) {
	if err := runSSH(hostConfig{}, []string{"opsro-broker", "status"}); err == nil || !strings.Contains(err.Error(), "missing address") {
		t.Fatalf("expected missing address error, got %v", err)
	}
}

func writeCaptureScript(t *testing.T, name, captureFile string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, name)
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" >\"" + captureFile + "\"\n"
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatalf("WriteFile(%s): %v", path, err)
	}
	return path
}

func writeConfigFile(t *testing.T, path string) string {
	t.Helper()
	content := `{
  "hosts": {
    "web-01": {
      "address": "10.0.1.12",
      "user": "opsro",
      "port": 2200
    }
  }
}`
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("MkdirAll(%s): %v", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("WriteFile(%s): %v", path, err)
	}
	return path
}

func readLines(t *testing.T, path string) []string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile(%s): %v", path, err)
	}
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" {
		return nil
	}
	return strings.Split(trimmed, "\n")
}
