ARG GO_VERSION=1.24
FROM golang:${GO_VERSION} AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
RUN CGO_ENABLED=0 GOOS=linux GOARCH=$(go env GOARCH) go build -o /out/opsro ./cmd/opsro

FROM debian:bookworm-slim
ARG TARGETARCH
ARG KUBECTL_VERSION=v1.34.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
RUN ARCH="${TARGETARCH}" \
    && if [ -z "$ARCH" ]; then \
         case "$(uname -m)" in \
           x86_64) ARCH=amd64 ;; \
           aarch64|arm64) ARCH=arm64 ;; \
           *) echo "unsupported architecture: $(uname -m)" && exit 1 ;; \
         esac; \
       fi \
    && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl
COPY --from=build /out/opsro /usr/local/bin/opsro
ENTRYPOINT ["/usr/local/bin/opsro"]
