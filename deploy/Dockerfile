FROM golang:1.22 AS builder
WORKDIR /app
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
RUN CGO_ENABLED=0 go build -o borderx-panel ./cmd/panel/

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /app/borderx-panel /usr/local/bin/
EXPOSE 8080
VOLUME ["/data"]
ENV TZ=Asia/Shanghai
CMD ["/usr/local/bin/borderx-panel", "--data-dir", "/data"]
