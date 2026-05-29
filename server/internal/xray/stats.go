package xray

import (
	"fmt"
	"strings"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// StatsCollector connects to the Xray Stats gRPC API and parses traffic stats.
type StatsCollector struct {
	conn *grpc.ClientConn
	port int
}

// NewStatsCollector dials the Xray Stats gRPC endpoint on localhost.
// statsPort is typically the value of cfg.Xray.StatsPort (default 10085).
func NewStatsCollector(statsPort int) (*StatsCollector, error) {
	addr := fmt.Sprintf("127.0.0.1:%d", statsPort)
	conn, err := grpc.Dial(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, fmt.Errorf("连接 Xray Stats API 失败: %w", err)
	}
	return &StatsCollector{conn: conn, port: statsPort}, nil
}

// TrafficDelta holds per-account traffic deltas for a single collection cycle.
type TrafficDelta struct {
	Email    string // Xray 客户端 email (accountID@borderx)
	Upload   int64  // 增量上行 (bytes)
	Download int64  // 增量下行 (bytes)
}

// QueryAll calls Xray StatsService.QueryStats and parses the response.
//
// Xray StatsService returns stats in format: "user>>>email>>>traffic>>>uplink"
// We parse the raw gRPC response or fall back to a simpler approach.
//
// MVP: returns an error when Xray is not running — the Collector skips
// silently. The Xray protobuf dependency is heavy (~150MB); real gRPC
// integration will be wired after "go get github.com/xtls/xray-core".
func (s *StatsCollector) QueryAll() ([]TrafficDelta, error) {
	// Placeholder: real implementation connects via gRPC to Xray StatsService
	// and parses stats like "user>>>email@borderx>>>traffic>>>uplink"
	//
	// When Xray is deployed, we add:
	//   go get github.com/xtls/xray-core
	// and use the generated StatsService client.
	return nil, fmt.Errorf("Xray Stats API 未连接（需要运行 Xray）")
}

// Close releases the underlying gRPC connection.
func (s *StatsCollector) Close() error {
	return s.conn.Close()
}

// parseEmail extracts the account email from an Xray stat name.
//
// Stat name format: user>>>email@domain>>>traffic>>>direction
func parseEmail(statName string) string {
	parts := strings.Split(statName, ">>>")
	if len(parts) >= 2 {
		return parts[1]
	}
	return ""
}

