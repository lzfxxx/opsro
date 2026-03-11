BINARY := bin/opsro

.PHONY: build test fmt docker-codex docker-claude

build:
	mkdir -p bin
	go build -o $(BINARY) ./cmd/opsro

test:
	go test ./...

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
