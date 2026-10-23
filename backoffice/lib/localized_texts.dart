/// A localized text of the content format: an object holding at least a
/// French string, at [pointer] in a document.
class LocalizedText {
  const LocalizedText(this.pointer, this.values);

  final List<String> pointer;

  /// Texts by locale (fr, en); a missing locale is absent.
  final Map<String, String> values;
}

const locales = ['fr', 'en'];

/// Every localized text of [document], in document order.
List<LocalizedText> localizedTexts(Object? document) {
  final found = <LocalizedText>[];
  void walk(Object? node, List<String> pointer) {
    if (node is Map<String, Object?>) {
      if (node['fr'] is String) {
        found.add(
          LocalizedText(pointer, {
            for (final l in locales)
              if (node[l] is String) l: node[l]! as String,
          }),
        );
        return;
      }
      node.forEach((key, value) => walk(value, [...pointer, key]));
    } else if (node is List<Object?>) {
      for (var i = 0; i < node.length; i++) {
        walk(node[i], [...pointer, '$i']);
      }
    }
  }

  walk(document, const []);
  return found;
}
