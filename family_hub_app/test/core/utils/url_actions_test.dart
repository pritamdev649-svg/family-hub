import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/core/utils/url_actions.dart';

void main() {
  group('UrlActions', () {
    test('URI builders', () {
      expect(
        UrlActions.telUri('+91 98765-43210').toString(),
        'tel:+919876543210',
      );
      expect(UrlActions.telUri('abc'), isNull);
      expect(
        UrlActions.mapUri(28.6139, 77.209).toString(),
        'https://www.google.com/maps/search/?api=1&query=28.613900%2C77.209000',
      );
      expect(UrlActions.mapUri(91, 0), isNull);
      expect(
        UrlActions.webUri('example.com').toString(),
        'https://example.com',
      );
      expect(
        UrlActions.webUri('http://x.org/a?b=1').toString(),
        'http://x.org/a?b=1',
      );
      expect(UrlActions.webUri('tel:112').toString(), 'tel:112');
      expect(UrlActions.webUri('javascript:alert(1)'), isNull);
      expect(UrlActions.webUri('https://'), isNull);
      expect(UrlActions.webUri('  '), isNull);
    });

    test('launches through the platform and never throws', () async {
      final launched = <Uri>[];
      UrlActions.launcherOverride = (uri, mode) async {
        launched.add(uri);
        if (uri.scheme == 'mailto') throw StateError('no mail app');
        return true;
      };
      addTearDown(() => UrlActions.launcherOverride = null);

      expect(await UrlActions.call('112'), isTrue);
      expect(await UrlActions.openMap(1, 2), isTrue);
      expect(await UrlActions.openUrl('familyhub.app'), isTrue);
      expect(await UrlActions.email('a@b.co'), isFalse);
      expect(await UrlActions.email('not-an-email'), isFalse);
      expect(await UrlActions.call(''), isFalse);
      expect(launched.map((u) => u.scheme), [
        'tel',
        'https',
        'https',
        'mailto',
      ]);
    });
  });
}
