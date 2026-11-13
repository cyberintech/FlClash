package core

import (
	"slices"
	"time"
)

const (
	adaptiveActive   = 6 * time.Second
	adaptiveReserve  = 40 * time.Second
	adaptiveCooldown = 120 * time.Second
	adaptiveHold     = 300 * time.Second
)

type adaptiveRoute struct {
	last                         time.Time
	ok                           bool
	failures, successes, backoff int
	pauseUntil                   time.Time
}

type adaptiveState struct {
	routes     map[string]adaptiveRoute
	selected   string
	lastSwitch time.Time
}

type adaptiveDecision struct {
	warm          []string
	probe, target string
	failed        bool
}

func (s *adaptiveState) observe(name string, ok bool, now time.Time) {
	r := s.routes[name]
	r.last, r.ok = now, ok
	if ok {
		r.failures, r.successes, r.backoff = 0, r.successes+1, 0
		r.pauseUntil = time.Time{}
	} else {
		r.failures++
		r.successes = 0
		if r.failures >= 2 {
			r.pauseUntil = now.Add(min(adaptiveCooldown*time.Duration(1<<r.backoff), 30*time.Minute))
			r.backoff = min(r.backoff+1, 3)
		}
	}
	s.routes[name] = r
}

func (s *adaptiveState) decide(names []string, current string, now time.Time) adaptiveDecision {
	if s.routes == nil {
		s.routes = map[string]adaptiveRoute{}
	}
	for n := range s.routes {
		if !slices.Contains(names, n) {
			delete(s.routes, n)
		}
	}
	if s.selected != current || s.lastSwitch.IsZero() {
		s.selected, s.lastSwitch = current, now
	}
	good := func(n string) bool {
		r := s.routes[n]
		return r.ok && now.Sub(r.last) <= 3*adaptiveReserve && !now.Before(r.pauseUntil)
	}
	due := func(n string, interval time.Duration) bool { return now.Sub(s.routes[n].last) >= interval }
	available := []string{}
	for _, n := range names {
		if n != current && !now.Before(s.routes[n].pauseUntil) {
			available = append(available, n)
		}
	}
	ranked := func(pool, against []string) string {
		best, score := "", -1
		for _, n := range pool {
			value := 0
			if good(n) {
				value += 10000
			}
			for _, other := range against {
				if other != "" {
					value += adaptiveDiversity(n, other)
				}
			}
			if value > score {
				best, score = n, value
			}
		}
		return best
	}
	first := ranked(available, []string{current})
	second := ""
	for _, n := range available {
		if n != first && slices.Index(names, n) < slices.Index(names, current) {
			second = n
			break
		}
	}
	if second == "" {
		pool := []string{}
		for _, n := range available {
			if n != first {
				pool = append(pool, n)
			}
		}
		second = ranked(pool, []string{current, first})
	}
	d := adaptiveDecision{}
	for _, n := range []string{first, second} {
		if n != "" {
			d.warm = append(d.warm, n)
		}
	}
	failed := s.routes[current].failures >= 2
	for _, n := range names {
		if n == current || !good(n) {
			continue
		}
		if failed {
			d.target, d.failed = n, true
			return d
		}
		if slices.Index(names, n) < slices.Index(names, current) && s.routes[n].successes >= 3 && now.Sub(s.lastSwitch) >= adaptiveHold {
			d.target = n
			return d
		}
	}
	if (!failed || !now.Before(s.routes[current].pauseUntil)) && due(current, adaptiveActive) {
		d.probe = current
		return d
	}
	if failed && len(available) == 0 {
		for _, n := range names {
			if due(n, 20*time.Second) && (d.probe == "" || s.routes[n].last.Before(s.routes[d.probe].last)) {
				d.probe = n
			}
		}
		return d
	}
	interval := adaptiveReserve
	if failed {
		interval = adaptiveActive
	}
	for _, n := range d.warm {
		if due(n, interval) && (d.probe == "" || s.routes[n].last.Before(s.routes[d.probe].last)) {
			d.probe = n
		}
	}
	return d
}

func adaptiveDiversity(a, b string) int {
	an, ap, af, _ := adaptiveRouteParts(a)
	bn, bp, bf, _ := adaptiveRouteParts(b)
	score := 0
	if an != bn {
		score += 100
	}
	if ap != bp {
		score += 30
	}
	if af != bf {
		score += 5
	}
	return score
}
