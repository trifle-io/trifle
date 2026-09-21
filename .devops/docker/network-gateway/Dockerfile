# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM golang:1.27.1-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags='-s -w' -o /out/network-gateway . \
    && mkdir -p /data && chmod 0700 /data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/network-gateway /network-gateway
COPY --from=builder --chown=65532:65532 /data /data
USER 65532:65532
EXPOSE 8443
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s CMD ["/network-gateway", "healthcheck"]
ENTRYPOINT ["/network-gateway"]
