package core

import (
	"testing"

	"github.com/metacubex/mihomo/config"
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
