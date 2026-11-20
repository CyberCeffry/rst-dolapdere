/// Türkçe harf duyarlı sıralama ve arama yardımcıları.
class TurkishText {
  static const _alphabet = 'abcçdefgğhıijklmnoöprsştuüvwxyz';

  /// Türkçe kurallarıyla küçük harfe çevirir (I→ı, İ→i).
  static String lower(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      switch (char) {
        case 'I':
          buffer.write('ı');
        case 'İ':
          buffer.write('i');
        default:
          buffer.write(char.toLowerCase());
      }
    }
    return buffer.toString();
  }

  /// Arama için: küçük harf + Türkçe karakterleri sadeleştirir (ş→s, ı→i ...).
  static String fold(String value) {
    const map = {
      'ı': 'i',
      'ş': 's',
      'ç': 'c',
      'ğ': 'g',
      'ö': 'o',
      'ü': 'u',
      'â': 'a',
      'î': 'i',
      'û': 'u',
    };
    final buffer = StringBuffer();
    for (final rune in lower(value).runes) {
      final char = String.fromCharCode(rune);
      buffer.write(map[char] ?? char);
    }
    return buffer.toString();
  }

  static int _rank(String char) {
    final index = _alphabet.indexOf(char);
    if (index >= 0) return index + 100;
    final code = char.codeUnitAt(0);
    return code < 100 ? code : code + 1000;
  }

  /// A→Z sıralama karşılaştırıcısı (Ç, Ğ, İ, Ö, Ş, Ü doğru yerde).
  static int compare(String a, String b) {
    final x = lower(a).trim();
    final y = lower(b).trim();
    final length = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < length; i++) {
      final rx = _rank(x[i]);
      final ry = _rank(y[i]);
      if (rx != ry) return rx.compareTo(ry);
    }
    return x.length.compareTo(y.length);
  }
}