# ---------------------------------------------------------------------------
# Dockerfile for demo-api — multi-stage build:
#   stage 1: compile the Go binary (compiler image is ~300MB, never shipped)
#   stage 2: minimal runtime image (~10MB) that only contains the binary
#
# Build:   docker build -t demo-api:0.1.0 .
# Run:     docker run -p 8080:8080 demo-api:0.1.0
# ---------------------------------------------------------------------------

FROM golang:1.26-alpine AS build
WORKDIR /src

# Copy dependency files first and download them — this layer is cached as long
# as go.mod/go.sum do not change, which makes rebuilds fast.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/demo-api .

# --- runtime stage ---------------------------------------------------------
FROM alpine:3.22
RUN adduser -D -u 10001 appuser          # never run containers as root
COPY --from=build /out/demo-api /demo-api

USER appuser
EXPOSE 8080
ENTRYPOINT ["/demo-api"]
