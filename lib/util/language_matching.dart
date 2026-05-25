const Map<String, String> _lang2To3 = {
  'en': 'eng',
  'es': 'spa',
  'fr': 'fra',
  'de': 'deu',
  'it': 'ita',
  'pt': 'por',
  'ja': 'jpn',
  'ko': 'kor',
  'zh': 'zho',
  'ru': 'rus',
  'ar': 'ara',
  'hi': 'hin',
  'nl': 'nld',
  'sv': 'swe',
  'no': 'nor',
  'da': 'dan',
  'fi': 'fin',
  'pl': 'pol',
};

bool languageMatchesPreferred(
  String? streamLanguage,
  String preferredNormalized,
  String preferredIso3,
) {
  final stream = normalizeLanguage(streamLanguage);
  if (stream.isEmpty || preferredNormalized.isEmpty) {
    return false;
  }
  if (stream == preferredNormalized) {
    return true;
  }

  final stream3 = toIso3Language(stream);
  return stream3.isNotEmpty && stream3 == preferredIso3;
}

String normalizeLanguage(String? language) {
  if (language == null) {
    return '';
  }
  final normalized = language.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized.split(RegExp(r'[-_]')).first;
}

String toIso3Language(String language) {
  if (language.length == 3) {
    return language;
  }
  return _lang2To3[language] ?? language;
}
