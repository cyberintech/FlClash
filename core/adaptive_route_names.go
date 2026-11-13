package core

import "strings"

func isManagedAdaptiveRoute(name string) bool {
	parts := strings.Split(name, "-")
	if len(parts) == 2 {
		city, route := parts[0], parts[1]
		return (city == "LN" || city == "LA" || city == "DE") &&
			(route == "V4" || route == "V6" || route == "S4" || route == "S6")
	}
	return len(parts) == 3 && (parts[0] == "LON" || parts[0] == "LA" || parts[0] == "DE") &&
		(parts[1] == "Vision" || parts[1] == "Salamander") && (parts[2] == "IPv4" || parts[2] == "IPv6")
}
