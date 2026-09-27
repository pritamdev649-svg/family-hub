import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the dialer, maps, browser or mail app. Every method returns
/// `false` (never throws) when the input is invalid or nothing can handle
/// the URL, so callers can show a localized "couldn't open" message.
abstract final class UrlActions {
  /// Hook for tests: replaces the platform launcher.
  @visibleForTesting
  static Future<bool> Function(Uri uri, LaunchMode mode)? launcherOverride;

  /// Dials [phone] (spaces, dashes, dots and parentheses are stripped).
  static Future<bool> call(String phone) {
    final uri = telUri(phone);
    if (uri == null) return Future.value(false);
    return _launch(uri, LaunchMode.externalApplication);
  }

  /// Opens a map pin. The Google Maps search URL works on Android, iOS and
  /// web (it opens the Maps app when installed, the browser otherwise).
  /// [label] is kept for API symmetry; the coordinates are what the pin
  /// shows.
  static Future<bool> openMap(double lat, double lng, {String? label}) {
    final uri = mapUri(lat, lng);
    if (uri == null) return Future.value(false);
    return _launch(uri, LaunchMode.externalApplication);
  }

  /// Opens [url] in the browser / handling app. `example.com` gets
  /// `https://`; only http, https, mailto and tel schemes are allowed.
  static Future<bool> openUrl(String url) {
    final uri = webUri(url);
    if (uri == null) return Future.value(false);
    return _launch(uri, LaunchMode.externalApplication);
  }

  /// Opens the mail composer for [to].
  static Future<bool> email(String to) {
    final address = to.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(address)) {
      return Future.value(false);
    }
    return _launch(
      Uri(scheme: 'mailto', path: address),
      LaunchMode.externalApplication,
    );
  }

  /// `tel:` URI for [phone] or null when it has no digits.
  static Uri? telUri(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[\s\-().]'), '');
    if (!RegExp(r'^\+?[\d*#]{2,}$').hasMatch(cleaned)) return null;
    return Uri(scheme: 'tel', path: cleaned);
  }

  /// Google Maps search URL for a coordinate, or null when out of range.
  static Uri? mapUri(double lat, double lng) {
    if (lat.isNaN || lng.isNaN || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
    });
  }

  static const _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

  /// Parsed, allowed URI for [url] or null.
  static Uri? webUri(String url) {
    var text = url.trim();
    if (text.isEmpty) return null;
    // Bare hosts (`example.com`, `example.com:8080/x`) default to https;
    // anything with another scheme (`javascript:`…) is rejected below.
    final lower = text.toLowerCase();
    final hasScheme =
        lower.startsWith('tel:') ||
        lower.startsWith('mailto:') ||
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:(?!\d)').hasMatch(text);
    if (!hasScheme) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || !_allowedSchemes.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static Future<bool> _launch(Uri uri, LaunchMode mode) async {
    try {
      final override = launcherOverride;
      if (override != null) return await override(uri, mode);
      return await launchUrl(uri, mode: mode);
    } catch (e) {
      debugPrint('UrlActions: cannot open $uri ($e)');
      return false;
    }
  }
}
