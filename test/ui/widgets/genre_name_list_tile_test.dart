import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/genre_name_list_tile.dart';

void main() {
  test('GenreListItem stores id and name with no image fields', () {
    final genre = GenreListItem(id: 'g1', name: 'Comedy');

    expect(genre.id, 'g1');
    expect(genre.name, 'Comedy');
  });

  group('GenreNameListTile', () {
    testWidgets('renders genre name and calls onTap when activated', (
      tester,
    ) async {
      var tapped = false;
      final genre = GenreListItem(id: 'g1', name: 'Comedy');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenreNameListTile(
              genre: genre,
              selected: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Comedy'), findsOneWidget);

      await tester.tap(find.byType(GenreNameListTile));
      await tester.pumpAndSettle();

      expect(tapped, true);
    });
  });
}
