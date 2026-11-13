package core

import (
	"context"
	"strings"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func prepareManagedAdaptive(raw *config.RawConfig) {
	if _, ok := raw.RuleProvider["VPN-Shared-VPN"]; !ok {
		return
	}
	if _, ok := raw.RuleProvider["VPN-Shared-Direct"]; !ok {
		return
	}
	outer, inner := -1, -1
	for i, g := range raw.ProxyGroup {
		if g["name"] == "VPN" && g["type"] == "select" {
			outer = i
		}
		if g["name"] == "VPN-AUTO" && g["type"] == "fallback" {
			inner = i
		}
	}
	if outer < 0 || inner < 0 {
		return
	}
	raw.ProxyGroup[inner]["type"] = "select"
	raw.ProxyGroup[inner]["interval"] = 0
	delete(raw.ProxyGroup[inner], "url")
	for name, p := range raw.ProxyProvider {
		if strings.HasPrefix(name, "VPN-Paths-") {
			p["health-check"] = map[string]any{"enable": false}
		}
	}
}

type adaptiveRuntime struct {
	state adaptiveState
	group C.Proxy
	epoch uint64
}

func managedAdaptiveSnapshot() (C.Proxy, outboundgroup.ProxyGroup, string, []string) {
	all := tunnel.AllProxies()
	outer, ok := adapterAs[pickableGroup](all["VPN"])
	if !ok || outer.Now() != "VPN-AUTO" {
		return nil, nil, "", nil
	}
	proxy := all["VPN-AUTO"]
	if proxy == nil || proxy.Type() != C.Selector {
		return nil, nil, "", nil
	}
	group, ok := adapterAs[pickableGroup](proxy)
	if !ok {
		return nil, nil, "", nil
	}
	names := []string{}
	for _, p := range group.Proxies() {
		parts := strings.Split(p.Name(), "-")
		if len(parts) == 3 && (parts[0] == "LON" || parts[0] == "LA" || parts[0] == "DE") &&
			(parts[1] == "Vision" || parts[1] == "Salamander") && (parts[2] == "IPv4" || parts[2] == "IPv6") {
			names = append(names, p.Name())
		}
	}
	if len(names) == 0 || len(names) > 128 {
		return nil, nil, "", nil
	}
	return proxy, group, group.Now(), names
}

func (a *adaptiveRuntime) tick(ctx context.Context) {
	selectMu.Lock()
	proxy, _, current, names := managedAdaptiveSnapshot()
	if proxy == nil {
		a.state = adaptiveState{}
		a.group = nil
		selectMu.Unlock()
		return
	}
	epoch, _ := routeStamp()
	if proxy != a.group || epoch != a.epoch {
		a.state, a.group, a.epoch = adaptiveState{}, proxy, epoch
	}
	now := time.Now()
	d := a.state.decide(names, current, now)
	probe := lookupProxy(d.probe)
	selectMu.Unlock()
	if probe != nil {
		testCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		expected, _ := utils.NewUnsignedRanges[uint16]("204")
		_, err := probe.URLTest(testCtx, defaultTestURL, expected)
		cancel()
		if ctx.Err() != nil {
			return
		}
		a.state.observe(d.probe, err == nil, time.Now())
		d = a.state.decide(names, current, time.Now())
	}
	if d.target == "" || ctx.Err() != nil {
		return
	}
	selectMu.Lock()
	defer selectMu.Unlock()
	live, _, selected, _ := managedAdaptiveSnapshot()
	liveEpoch, _ := routeStamp()
	if live != proxy || selected != current || liveEpoch != epoch || !isRunning.Load() {
		return
	}
	selector, ok := adapterAs[outboundgroup.SelectAble](live)
	if !ok || selector.Set(d.target) != nil {
		return
	}
	a.state.selected, a.state.lastSwitch = d.target, time.Now()
	refreshRouteLocked(routeMoved)
}
