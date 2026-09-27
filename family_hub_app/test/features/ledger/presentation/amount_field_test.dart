import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/features/ledger/presentation/widgets/amount_field.dart';

String _type(DecimalAmountInputFormatter f, String old, String next) => f
    .formatEditUpdate(TextEditingValue(text: old), TextEditingValue(text: next))
    .text;

void main() {
  group('DecimalAmountInputFormatter (dot decimal)', () {
    final f = DecimalAmountInputFormatter();

    test('accepts digits, grouping and up to two decimals', () {
      expect(_type(f, '', '1'), '1');
      expect(_type(f, '1', '1250.5'), '1250.5');
      expect(_type(f, '1250.5', '1250.55'), '1250.55');
      expect(_type(f, '', '1,25,000.75'), '1,25,000.75');
      expect(_type(f, '', '१२५०'), '१२५०'); // Devanagari digits
      expect(_type(f, '', '١٢٫٥'), '١٢٫٥'); // Arabic digits + decimal sign
    });

    test(
      'rejects a third decimal, a second separator and other characters',
      () {
        expect(_type(f, '1250.55', '1250.555'), '1250.55');
        expect(_type(f, '12.5', '12.5.'), '12.5');
        expect(_type(f, '12', '12a'), '12');
        expect(_type(f, '', '-5'), '');
        // Grouping marks are not allowed after the decimal separator.
        expect(_type(f, '12.5', '12.5,'), '12.5');
      },
    );

    test('limits the length', () {
      final short = DecimalAmountInputFormatter(maxLength: 5);
      expect(_type(short, '12345', '123456'), '12345');
    });

    test('clearing is always allowed', () {
      expect(_type(f, '12.5', ''), '');
    });
  });

  group('DecimalAmountInputFormatter (comma decimal)', () {
    final f = DecimalAmountInputFormatter(decimalSeparator: ',');

    test('uses comma as decimal and dot as grouping', () {
      expect(_type(f, '', '1.250,50'), '1.250,50');
      expect(_type(f, '1.250,50', '1.250,505'), '1.250,50');
      expect(_type(f, '1,5', '1,5,'), '1,5');
    });
  });

  test('textFor prints an amount for editing', () {
    expect(DecimalAmountInputFormatter.textFor(60000), '60000');
    expect(DecimalAmountInputFormatter.textFor(1250.5), '1250.5');
    expect(DecimalAmountInputFormatter.textFor(1250.505), '1250.51');
    expect(
      DecimalAmountInputFormatter.textFor(99.9, decimalSeparator: ','),
      '99,9',
    );
    expect(DecimalAmountInputFormatter.textFor(0), '');
    expect(DecimalAmountInputFormatter.textFor(double.nan), '');
  });
}
