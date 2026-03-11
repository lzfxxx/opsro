BINARY := bin/opsro

.PHONY: build test fmt

build:
	mkdir -p bin
	go build -o $(BINARY) ./cmd/opsro

test:
	go test ./...

fmt:
	gofmt -w ./cmd
