BINARY := bin/opsro

.PHONY: build test test-shell fmt docker-codex docker-claude

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

build:
	mkdir -p bin
	go build -ldflags "-X main.version=$(VERSION)" -o $(BINARY) ./cmd/opsro

test: test-shell
	go test ./...

test-shell:
	chmod +x scripts/install.sh scripts/bootstrap.sh scripts/install-k8s-readonly.sh scripts/install-host-broker.sh tests/*.sh
	./tests/install_test.sh
	./tests/installers_test.sh
	./tests/broker_test.sh
	./tests/bootstrap_test.sh
	./tests/container_scripts_test.sh

fmt:
	gofmt -w ./cmd

docker-codex:
	docker build -f Dockerfile.agent \
	  --build-arg AGENT_PACKAGE=@openai/codex \
	  --build-arg AGENT_BIN=codex \
	  -t opsro-codex:dev .

docker-claude:
	docker build -f Dockerfile.agent \
	  --build-arg AGENT_PACKAGE=@anthropic-ai/claude-code \
	  --build-arg AGENT_BIN=claude \
	  -t opsro-claude:dev .
