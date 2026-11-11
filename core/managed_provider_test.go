package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// A managed subscription uses an HTTP provider, so its cached nodes must be
// visible through the exact group view consumed by the host, even offline.
func TestManagedProviderCacheShows72RoutesWithoutCompatible(t *testing.T) {
	home := t.TempDir()
	previous := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir(previous) })
	keepTunnel(t)

	nodes := make([]map[string]any, 72)
	for i := range nodes {
		nodes[i] = map[string]any{"name": fmt.Sprintf("route-%02d", i), "type": "socks5", "server": "127.0.0.1", "port": 9}
	}
	payload, err := json.Marshal(map[string]any{"proxies": nodes})
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(home, "paths.yaml")
	if err = os.WriteFile(path, payload, 0600); err != nil {
		t.Fatal(err)
	}
	raw := fmt.Sprintf(`ipv6: true
proxy-providers:
  VPN-Paths:
    type: http
    url: http://127.0.0.1:1/offline
    path: %s
    interval: 0
    health-check: {enable: false}
proxy-groups:
  - {name: VPN, type: select, proxies: [VPN-AUTO], use: [VPN-Paths]}
  - {name: VPN-AUTO, type: fallback, use: [VPN-Paths], url: https://example.invalid/test, interval: 0}
rules: ["MATCH,DIRECT"]
`, path)
	cfg, err := config.Parse([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	for _, pd := range cfg.Providers {
		if closer, ok := pd.(interface{ Close() error }); ok {
			t.Cleanup(func() { _ = closer.Close() })
		}
		if err = pd.Initial(); err != nil {
			t.Fatal(err)
		}
	}
	tunnel.UpdateProxies(cfg.Proxies, cfg.Providers)
	view, err := groupView(cfg.Proxies["VPN-AUTO"])
	if err != nil {
		t.Fatal(err)
	}
	var group struct {
		All []string `json:"all"`
	}
	if err = json.Unmarshal(view, &group); err != nil {
		t.Fatal(err)
	}
	if len(group.All) != 72 {
		t.Fatalf("VPN-AUTO exposes %d nodes, want72", len(group.All))
	}
	for _, name := range group.All {
		if name == "COMPATIBLE" || name == "Compatible" {
			t.Fatal("placeholder leaked into managed group")
		}
	}
	if got := handleGetExternalProvider(NameParams{Name: "VPN-Paths"}); got == nil || got.Count != 72 {
		t.Fatalf("external provider = %+v; want72 routes", got)
	}
}
