package core

import "strings"

// Return canonical failure domains for both old IDs and compact subscription names.
func adaptiveRouteParts(name string) (string, string, string, bool) {
	parts := strings.Split(name, "-")
	if len(parts) == 2 {
		node := parts[0]
		switch node {
		case "LN":
			node = "LON"
		case "LA", "DE":
		default:
			return name, "", "", false
		}
		route := parts[1]
		if len(route) != 2 || (route[1] != '4' && route[1] != '6') {
			return name, "", "", false
		}
		var protocol string
		switch route[0] {
		case 'V':
			protocol = "Vision"
		case 'S':
			protocol = "Salamander"
		case 'X':
			protocol = "XHTTP"
		case 'A':
			protocol = "AnyTLS"
		case 'T':
			protocol = "ShadowTLS"
		case 'Q':
			protocol = "TUIC"
		default:
			return name, "", "", false
		}
		return node, protocol, "IPv" + route[1:], true
	}
	if len(parts) == 3 && (parts[0] == "LON" || parts[0] == "LA" || parts[0] == "DE") &&
		(parts[1] == "Vision" || parts[1] == "Salamander" || parts[1] == "XHTTP" || parts[1] == "AnyTLS" || parts[1] == "ShadowTLS" || parts[1] == "TUIC") &&
		(parts[2] == "IPv4" || parts[2] == "IPv6") {
		return parts[0], parts[1], parts[2], true
	}
	return name, "", "", false
}

func isManagedAdaptiveRoute(name string) bool {
	_, _, _, ok := adaptiveRouteParts(name)
	return ok
}
