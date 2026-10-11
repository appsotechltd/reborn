import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the browser has the Web Share API (`navigator.share`); desktop
/// Chrome on Linux and Firefox don't, and share_plus then falls back to a
/// `mailto:` link that usually does nothing.
bool get platformCanShare {
  final nav = globalContext['navigator'];
  return nav != null && (nav as JSObject).has('share');
}
