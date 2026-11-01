import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Store listing rules (App Store Connect + Google Play Console) checked on
/// every test run, so a copy edit can never break a submission.
/// Files: `store/ios/<locale>/*.txt` and `store/android/<locale>/*.txt`
/// (fastlane deliver / supply layout).
String _read(String path) => File(path).readAsStringSync().trim();

int _chars(String s) => s.runes.length;
int _bytes(String s) => utf8.encode(s).length;

Set<String> _words(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-zçğıöşüâîû0-9]+'))
    .where((w) => w.isNotEmpty)
    .toSet();

final _emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);

/// Claims both stores reject (2.3.7 / Play metadata policy) and claims this
/// app must never make (it is not endorsed by FIDE).
const _bannedEverywhere = [
  'fide onaylı', 'fide approved', 'resmi fide', 'official fide', '#1',
  'en iyi', 'best ', 'number one', 'hemen indir', 'download now',
];

void main() {
  final iosLocales = Directory('store/ios')
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split('/').last)
      .where((l) => l != 'review_information')
      .toList();
  final androidLocales = Directory('store/android')
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split('/').last)
      .toList();

  test('locales present', () {
    expect(iosLocales, containsAll(['tr', 'en-GB']));
    expect(androidLocales, containsAll(['tr-TR', 'en-US']));
  });

  for (final l in iosLocales) {
    group('App Store $l', () {
      String f(String n) => _read('store/ios/$l/$n.txt');

      test('field limits', () {
        expect(_chars(f('name')), inInclusiveRange(2, 30));
        expect(_chars(f('subtitle')), lessThanOrEqualTo(30));
        expect(_bytes(f('keywords')), lessThanOrEqualTo(100));
        expect(_chars(f('promotional_text')), lessThanOrEqualTo(170));
        expect(_chars(f('description')), lessThanOrEqualTo(4000));
        expect(_chars(f('release_notes')), lessThanOrEqualTo(4000));
      });

      test('keywords: comma separated, no spaces, no repeats of name/subtitle', () {
        final kw = f('keywords');
        expect(kw.contains(', '), isFalse, reason: 'spaces waste keyword bytes');
        final list = kw.split(',');
        expect(list.toSet().length, list.length, reason: 'duplicate keyword');
        final indexed = _words('${f('name')} ${f('subtitle')}');
        for (final k in list) {
          expect(indexed.contains(k.toLowerCase()), isFalse,
              reason: '"$k" is already indexed from the name/subtitle');
        }
      });

      test('no other platforms in iOS metadata (2.3.10)', () {
        for (final n in ['name', 'subtitle', 'keywords', 'promotional_text', 'description',
          'release_notes']) {
          final t = f(n).toLowerCase();
          for (final banned in ['android', 'google play', 'play store']) {
            expect(t.contains(banned), isFalse, reason: '$n mentions $banned');
          }
        }
      });

      test('subscription disclosure and legal links (3.1.2)', () {
        final d = f('description');
        expect(d, contains('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'));
        expect(d, contains(f('privacy_url')));
        expect(d.toLowerCase(), anyOf(contains('24 saat'), contains('24 hours')));
      });

      test('no misleading claims', () {
        final all = [
          for (final n in ['name', 'subtitle', 'keywords', 'promotional_text', 'description'])
            f(n).toLowerCase(),
        ].join('\n');
        for (final b in _bannedEverywhere) {
          expect(all.contains(b), isFalse, reason: 'contains "$b"');
        }
        expect(_words('${f('name')} ${f('subtitle')} ${f('keywords')}').contains('fide'),
            isFalse,
            reason: 'trademark in indexed fields (2.3.7 / 5.2.1)');
        expect(_emoji.hasMatch(f('name')), isFalse);
      });

      test('urls are https', () {
        for (final n in ['privacy_url', 'support_url', 'marketing_url']) {
          expect(f(n), startsWith('https://'));
        }
      });
    });
  }

  test('App Store review notes explain how to reach every paid feature', () {
    final notes = _read('store/ios/review_information/notes.txt');
    expect(notes, contains('Örneği aç'));
    expect(notes, contains('Sandbox'));
    expect(_chars(notes), lessThanOrEqualTo(4000));
  });

  for (final l in androidLocales) {
    group('Google Play $l', () {
      String f(String n) => _read('store/android/$l/$n.txt');

      test('field limits', () {
        expect(_chars(f('title')), inInclusiveRange(2, 30));
        expect(_chars(f('short_description')), lessThanOrEqualTo(80));
        expect(_chars(f('full_description')), lessThanOrEqualTo(4000));
        expect(_chars(f('changelogs/1')), lessThanOrEqualTo(500));
      });

      test('no other platforms, emoji, caps or ranking claims', () {
        final all = [f('title'), f('short_description'), f('full_description')]
            .join('\n')
            .toLowerCase();
        for (final b in ['app store', 'iphone', 'ipad', 'apple', ..._bannedEverywhere]) {
          expect(all.contains(b), isFalse, reason: 'mentions "$b"');
        }
        expect(_emoji.hasMatch(f('title')), isFalse);
        expect(_emoji.hasMatch(f('short_description')), isFalse);
        expect(f('title') == f('title').toUpperCase(), isFalse, reason: 'all caps title');
      });

      test('subscription disclosure', () {
        final d = f('full_description').toLowerCase();
        expect(d, contains('google play'));
        expect(d, anyOf(contains('iptal'), contains('cancel')));
      });
    });
  }
}
