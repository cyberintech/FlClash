const _vpnRouteLabels = {
  'LON-Vision-IPv4': 'LN-V4',
  'LON-Vision-IPv6': 'LN-V6',
  'LON-Salamander-IPv4': 'LN-S4',
  'LON-Salamander-IPv6': 'LN-S6',
  'LA-Vision-IPv4': 'LA-V4',
  'LA-Vision-IPv6': 'LA-V6',
  'LA-Salamander-IPv4': 'LA-S4',
  'LA-Salamander-IPv6': 'LA-S6',
  'DE-Vision-IPv4': 'DE-V4',
  'DE-Vision-IPv6': 'DE-V6',
  'DE-Salamander-IPv4': 'DE-S4',
  'DE-Salamander-IPv6': 'DE-S6',
};

String vpnRouteDisplayName(String name) => _vpnRouteLabels[name] ?? name;
