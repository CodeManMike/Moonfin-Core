import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/genre_name_list_tile.dart';

void main() {
  test('GenreListItem stores id and name with no image fields', () {
    final genre = GenreListItem(id: 'g1', name: 'Comedy');

    expect(genre.id, 'g1');
    expect(genre.name, 'Comedy');
  });
}
