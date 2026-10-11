import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Returns the device's IANA timezone (e.g. "Europe/London"), or null.
typedef TimezoneGetter = Future<String?> Function();

Future<String?> _deviceTimezone() async {
  try {
    final tz = await FlutterTimezone.getLocalTimezone();
    return tz.identifier.isEmpty ? null : tz.identifier;
  } catch (_) {
    return null;
  }
}

final deviceTimezoneProvider = Provider<TimezoneGetter>(
  (ref) => _deviceTimezone,
);
