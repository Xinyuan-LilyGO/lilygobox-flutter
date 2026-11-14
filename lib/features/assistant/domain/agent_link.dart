/// Canonical link to an existing agent conversation inside LilygoBox.
String agentLink(String id) =>
    Uri(scheme: 'lilygobox', host: 'agent', pathSegments: [id]).toString();

/// Reserve the app scheme even when malformed so it never launches externally.
bool isAgentLink(String? href) =>
    href != null && RegExp(r'^lilygobox:', caseSensitive: false).hasMatch(href);

/// Returns a valid exact agent ID; the caller checks agent existence.
String? agentIdFromLink(String? href) {
  if (href == null || RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(href)) {
    return null;
  }
  try {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.scheme != 'lilygobox' ||
        uri.host != 'agent' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1 ||
        !RegExp(r'^\d+-\d+$').hasMatch(uri.pathSegments.single)) {
      return null;
    }
    return uri.pathSegments.single;
  } on FormatException {
    return null;
  }
}
