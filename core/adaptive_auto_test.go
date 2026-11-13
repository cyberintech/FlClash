package core

import (
	"slices"
	"testing"
	"time"
)

var adaptiveNames = []string{"LON-Vision-IPv6", "LA-Salamander-IPv4", "DE-Vision-IPv4", "LON-Salamander-IPv4"}

func TestAdaptiveConfirmedFailureAndStaleReserve(t *testing.T) {
	now := time.Now()
	s := adaptiveState{}
	s.decide(adaptiveNames, adaptiveNames[0], now)
	s.observe(adaptiveNames[1], true, now)
	s.observe(adaptiveNames[0], false, now)
	if d := s.decide(adaptiveNames, adaptiveNames[0], now); d.target != "" {
		t.Fatal("single failure switched", d)
	}
	s.observe(adaptiveNames[0], false, now.Add(adaptiveActive))
	d := s.decide(adaptiveNames, adaptiveNames[0], now.Add(adaptiveActive))
	if d.target != adaptiveNames[1] || !d.failed {
		t.Fatal("fresh reserve not selected", d)
	}
	if !s.routes[adaptiveNames[0]].pauseUntil.After(now) {
		t.Fatal("failed route was not paused")
	}
	s.routes[adaptiveNames[1]] = adaptiveRoute{last: now.Add(-10 * time.Minute), ok: true}
	if d := s.decide(adaptiveNames, adaptiveNames[0], now); d.target != "" {
		t.Fatal("stale reserve selected", d)
	}
}

func TestAdaptiveHoldAndThreeSuccesses(t *testing.T) {
	now := time.Now()
	s := adaptiveState{}
	s.decide(adaptiveNames, adaptiveNames[1], now)
	for range 2 {
		s.observe(adaptiveNames[0], true, now.Add(adaptiveHold))
	}
	if d := s.decide(adaptiveNames, adaptiveNames[1], now.Add(adaptiveHold)); d.target != "" {
		t.Fatal("unconfirmed failback", d)
	}
	s.observe(adaptiveNames[0], true, now.Add(adaptiveHold))
	if d := s.decide(adaptiveNames, adaptiveNames[1], now.Add(adaptiveHold)); d.target != adaptiveNames[0] || d.failed {
		t.Fatal("confirmed recovery missing", d)
	}
}

func TestAdaptiveProbeBudgetAndDiversity(t *testing.T) {
	now := time.Now()
	s := adaptiveState{}
	observed := map[string]bool{}
	count := 0
	for i := 0; i < 60; i += 2 {
		at := now.Add(time.Duration(i) * time.Second)
		d := s.decide(adaptiveNames, adaptiveNames[0], at)
		if len(d.warm) != 2 || !slices.Contains(d.warm, adaptiveNames[1]) {
			t.Fatal("missing diverse reserves", d)
		}
		if d.probe != "" {
			count++
			observed[d.probe] = true
			s.observe(d.probe, true, at)
		}
	}
	if count > 16 || len(observed) > 3 {
		t.Fatalf("unbounded probing: %d probes on %d paths", count, len(observed))
	}
}

func TestAdaptiveMobileIPv6FailureFindsIPv4(t *testing.T) {
	names := []string{"LON-Vision-IPv6", "LON-Salamander-IPv6", "LA-Vision-IPv6", "LA-Salamander-IPv6", "LON-Vision-IPv4", "LON-Salamander-IPv4", "LA-Vision-IPv4", "LA-Salamander-IPv4", "DE-Vision-IPv6", "DE-Salamander-IPv6", "DE-Vision-IPv4", "DE-Salamander-IPv4"}
	now := time.Now()
	s := adaptiveState{}
	for i := 0; i <= 30; i += 2 {
		at := now.Add(time.Duration(i) * time.Second)
		d := s.decide(names, names[0], at)
		if d.probe != "" {
			s.observe(d.probe, d.probe == "LA-Salamander-IPv4", at)
		}
		d = s.decide(names, names[0], at)
		if d.target != "" {
			if d.target != "LA-Salamander-IPv4" {
				t.Fatal("bad mobile backup", d)
			}
			return
		}
	}
	t.Fatal("IPv4-only mobile did not recover within 30 seconds")
}

func TestAdaptiveHealthyCurrentAndManualInnerHold(t *testing.T) {
	now := time.Now()
	s := adaptiveState{}
	s.decide(adaptiveNames, adaptiveNames[0], now)
	for range 3 {
		s.observe(adaptiveNames[1], true, now)
	}
	if d := s.decide(adaptiveNames, adaptiveNames[0], now); d.target != "" {
		t.Fatal("healthy path replaced just for lower priority reserve", d)
	}
	s.decide(adaptiveNames, adaptiveNames[1], now.Add(time.Second))
	if !s.lastSwitch.Equal(now.Add(time.Second)) {
		t.Fatal("manual inner selection hold lost")
	}
}

func TestAdaptiveCompleteOutageStillProbesForNetworkRecovery(t *testing.T) {
	now := time.Now()
	s := adaptiveState{}
	s.decide(adaptiveNames, adaptiveNames[0], now)
	for _, n := range adaptiveNames {
		s.observe(n, false, now)
		s.observe(n, false, now)
	}
	if d := s.decide(adaptiveNames, adaptiveNames[0], now.Add(5*time.Second)); d.probe != "" {
		t.Fatal("outage probe too early", d)
	}
	if d := s.decide(adaptiveNames, adaptiveNames[0], now.Add(21*time.Second)); d.probe == "" {
		t.Fatal("network recovery starved", d)
	}
}
