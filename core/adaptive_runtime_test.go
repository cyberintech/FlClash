package core

import (
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/tunnel"
)

func TestAdaptiveManagedConfigOnly(t *testing.T) {
	raw := config.DefaultRawConfig()
	raw.ProxyGroup = []map[string]any{{"name": "VPN", "type": "select"}, {"name": "VPN-AUTO", "type": "fallback", "use": []string{"VPN-Paths-test"}}}
	prepareManagedAdaptive(raw)
	if raw.ProxyGroup[1]["type"] != "fallback" {
		t.Fatal("unmanaged config changed")
	}
	raw.RuleProvider = map[string]map[string]any{"VPN-Shared-VPN": {}, "VPN-Shared-Direct": {}}
	raw.ProxyProvider = map[string]map[string]any{"VPN-Paths-test": {"health-check": map[string]any{"enable": true}}, "unrelated": {"health-check": map[string]any{"enable": true}}}
	prepareManagedAdaptive(raw)
	if raw.ProxyGroup[1]["empty-fallback"] != "REJECT" {
		t.Fatal("empty managed route must fail closed")
	}
	if raw.ProxyGroup[1]["type"] != "select" {
		t.Fatal("adaptive owner not installed")
	}
	if raw.ProxyProvider["VPN-Paths-test"]["health-check"].(map[string]any)["enable"] != false {
		t.Fatal("duplicate native sweep retained")
	}
	if raw.ProxyProvider["unrelated"]["health-check"].(map[string]any)["enable"] != true {
		t.Fatal("unrelated provider changed")
	}
}

func TestAdaptiveFollowsActualRuleAndGlobalSelection(t *testing.T) {
	for _, tc := range []struct {
		name        string
		mode        tunnel.TunnelMode
		global, vpn string
		want        bool
	}{
		{"rule auto", tunnel.Rule, "DIRECT", "VPN-AUTO", true},
		{"rule manual", tunnel.Rule, "VPN-AUTO", "LON-Vision-IPv4", false},
		{"global auto ignores inactive manual VPN group", tunnel.Global, "VPN-AUTO", "DE-Vision-IPv4", true},
		{"global through VPN auto", tunnel.Global, "VPN", "VPN-AUTO", true},
		{"global manual", tunnel.Global, "LON-Vision-IPv4", "VPN-AUTO", false},
		{"global direct", tunnel.Global, "DIRECT", "VPN-AUTO", false},
		{"direct mode", tunnel.Direct, "VPN-AUTO", "VPN-AUTO", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := managedAutoActive(tc.mode, tc.global, tc.vpn); got != tc.want {
				t.Fatalf("active=%v, want %v", got, tc.want)
			}
		})
	}
}
