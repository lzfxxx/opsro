package main

import "testing"

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
