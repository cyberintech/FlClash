package core

import (
	"fmt"
	"testing"
)

func TestAdaptiveManagedRouteNames(t *testing.T) {
	for _, city := range []struct{ old, short string }{{"LON", "LN"}, {"LA", "LA"}, {"DE", "DE"}} {
		for _, protocol := range []struct{ old, short string }{{"Vision", "V"}, {"Salamander", "S"}} {
			for _, family := range []int{4, 6} {
				for _, name := range []string{fmt.Sprintf("%s-%s-IPv%d", city.old, protocol.old, family), fmt.Sprintf("%s-%s%d", city.short, protocol.short, family)} {
					if !isManagedAdaptiveRoute(name) {
						t.Fatalf("valid managed route rejected: %s", name)
					}
				}
			}
		}
	}
	for _, name := range []string{"", "DIRECT", "VPN-AUTO", "LA-V5", "LA-X4", "XX-V4", "LON-V4", "LA-Vision-via-EXP", "DE-S6-extra"} {
		if isManagedAdaptiveRoute(name) {
			t.Fatalf("unmanaged route accepted: %s", name)
		}
	}
}
