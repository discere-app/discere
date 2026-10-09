import 'package:discere/catalog/repository/fts_match_term.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replaces quotes and parentheses with spaces', () {
    expect(ftsMatchTerm('requins "tig'), 'requins tig');
    expect(ftsMatchTerm('(requins'), 'requins');
    expect(ftsMatchTerm('requins)'), 'requins');
    expect(ftsMatchTerm('"Blau Hai'), 'Blau Hai');
  });

  test('leaves the rest of the FTS syntax and the case alone', () {
    expect(ftsMatchTerm('Requins-Tig'), 'Requins-Tig');
    expect(ftsMatchTerm('name:requins'), 'name:requins');
    expect(ftsMatchTerm('^requins'), '^requins');
    expect(ftsMatchTerm('requins -tig'), 'requins -tig');
    expect(ftsMatchTerm("requin d'Australie"), "requin d'Australie");
    expect(ftsMatchTerm('requins AND tig'), 'requins AND tig');
  });

  test('collapses the whitespace a replacement leaves behind', () {
    expect(ftsMatchTerm('Blau  ( Hai )'), 'Blau Hai');
    expect(ftsMatchTerm(' requins\t"tig" '), 'requins tig');
  });

  test('leaves nothing when there is nothing but quotes and parentheses', () {
    expect(ftsMatchTerm(''), isEmpty);
    expect(ftsMatchTerm('"'), isEmpty);
    expect(ftsMatchTerm(' ( ) " '), isEmpty);
  });
}
