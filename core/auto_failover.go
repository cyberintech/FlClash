package core

import (
	"context"
	"slices"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// Managed profiles opt in through the VPN -> VPN-AUTO group contract.
// This watch belongs to the VPN core, not to a visible Flutter page.
const failoverPollInterval = 2 * time.Second

type autoPick struct {
	active    bool
	leaf      string
	oldExists bool
	oldAlive  bool
}

type failedPathState struct{ previous autoPick }

func (s *failedPathState) update(next autoPick) string {
	old := s.previous
	s.previous = next
	if !old.active || !next.active || old.leaf == "" || next.leaf == "" || old.leaf == next.leaf {
		return ""
	}
	if next.oldExists && !next.oldAlive {
		return old.leaf
	}
	return ""
}

func failedPathChain(chain []string, old string) bool {
	return old != "" && slices.Contains(chain, "VPN-AUTO") && slices.Contains(chain, old)
}

var autoFailureWatch struct {
	sync.Mutex
	cancel context.CancelFunc
}

func startAutoFailureWatch() {
	autoFailureWatch.Lock()
	defer autoFailureWatch.Unlock()
	if autoFailureWatch.cancel != nil {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	autoFailureWatch.cancel = cancel
	safeGo("VPN Policy auto failover", func() { pollAutoFailure(ctx) })
}

func stopAutoFailureWatch() {
	autoFailureWatch.Lock()
	defer autoFailureWatch.Unlock()
	if autoFailureWatch.cancel != nil {
		autoFailureWatch.cancel()
		autoFailureWatch.cancel = nil
	}
}

func resetAutoFailureWatch() {
	stopAutoFailureWatch()
	if isRunning.Load() {
		startAutoFailureWatch()
	}
}

func pollAutoFailure(ctx context.Context) {
	ticker := time.NewTicker(failoverPollInterval)
	defer ticker.Stop()
	state := failedPathState{}
	adaptive := adaptiveRuntime{}
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if !isRunning.Load() {
				state = failedPathState{}
				continue
			}
			adaptive.tick(ctx)
			configMu.Lock()
			if ctx.Err() != nil {
				configMu.Unlock()
				return
			}
			selectMu.Lock()
			next := readManagedAutoPick(state.previous.leaf)
			failed := state.update(next)
			selectMu.Unlock()
			var connections []statistic.Tracker
			if failed != "" {
				statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
					if info := c.Info(); info != nil && failedPathChain([]string(info.Chain), failed) {
						connections = append(connections, c)
					}
					return true
				})
			}
			configMu.Unlock()
			for _, c := range connections {
				_ = c.Close()
			}
			if len(connections) > 0 {
				log.Infoln("[VPN Policy] closed %d connections on failed AUTO path %s", len(connections), failed)
			}
		}
	}
}

// Caller holds configMu and selectMu, including around Fallback.Now().
func readManagedAutoPick(previous string) autoPick {
	all := tunnel.AllProxies()
	if !managedAutoRequested() {
		return autoPick{}
	}
	auto, ok := all["VPN-AUTO"]
	if !ok || (auto.Type() != C.Fallback && auto.Type() != C.Selector) {
		return autoPick{}
	}
	group, ok := auto.(*adapter.Proxy)
	if !ok {
		return autoPick{}
	}
	pick, ok := group.ProxyAdapter.(interface{ Now() string })
	if !ok {
		return autoPick{}
	}
	result := autoPick{active: true, leaf: pick.Now()}
	if old, exists := all[previous]; exists {
		result.oldExists = true
		result.oldAlive = old.AliveForTestUrl(defaultTestURL)
	}
	return result
}
