package core

import (
	"fmt"
	"testing"
)

func TestAdaptiveManagedRouteNames(t *testing.T) {
	for _, city := range []struct{ old, short string }{{"LON", "LN"}, {"LA", "LA"}, {"DE", "DE"}} {
		for _, protocol := range []struct{ old, short string }{{"Vision", "V"}, {"Salamander", "S"}, {"XHTTP", "X"}, {"AnyTLS", "A"}} {
			for _, family := range []int{4, 6} {
				for _, name := range []string{fmt.Sprintf("%s-%s-IPv%d", city.old, protocol.old, family), fmt.Sprintf("%s-%s%d", city.short, protocol.short, family)} {
					if !isManagedAdaptiveRoute(name) {
						t.Fatalf("valid managed route rejected: %s", name)
					}
				}
			}
		}
	}
	for _, name := range []string{"", "DIRECT", "VPN-AUTO", "LA-V5", "LA-Q4", "LA-X5", "DE-A5", "XX-V4", "LON-V4", "LA-Vision-via-EXP", "DE-S6-extra"} {
		if isManagedAdaptiveRoute(name) {
			t.Fatalf("unmanaged route accepted: %s", name)
		}
	}
}

func TestAdaptiveCompactNamesPreserveFailureDomains(t *testing.T) {
	for _, pair := range [][2]string{{"LN-V4", "LON-Vision-IPv4"}, {"LA-X6", "LA-XHTTP-IPv6"}, {"DE-A4", "DE-AnyTLS-IPv4"}} {
		if got := adaptiveDiversity(pair[0], pair[1]); got != 0 {
			t.Fatalf("same route domains differ: %v score=%d", pair, got)
		}
	}
	for _, tc := range []struct {
		a, b string
		want int
	}{{"LN-V4", "LN-X4", 30}, {"LN-X4", "LN-X6", 5}, {"LN-X4", "LA-X4", 100}, {"LN-X4", "LA-A6", 135}} {
		if got := adaptiveDiversity(tc.a, tc.b); got != tc.want {
			t.Fatalf("diversity %s/%s=%d want%d", tc.a, tc.b, got, tc.want)
		}
	}
}
