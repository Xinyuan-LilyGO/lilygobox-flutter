import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/core/widgets/desktop_card_selection.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('click, additive toggle, anchored range, and pruning', () {
    final selection = DesktopCardSelection();
    const ids = ['a', 'b', 'c', 'd', 'e'];
    selection.select('b', ids);
    selection.select('d', ids, shift: true);
    expect(selection.selected, {'b', 'c', 'd'});
    selection.select('c', ids, control: true);
    expect(selection.selected, {'b', 'd'});
    selection.select('a', ids, control: true, shift: true);
    expect(selection.selected, {'a', 'b', 'c', 'd'});
    selection.select('e', ids);
    expect(selection.selected, {'e'});
    selection.selectAll(ids);
    selection.retain(['b', 'd']);
    expect(selection.selected, {'b', 'd'});
    expect(selection.anchor, isNull);
    selection.clear();
    expect(selection.selected, isEmpty);
  });

  testWidgets('list shortcuts never delete selections from a text editor', (
    tester,
  ) async {
    final selection = DesktopCardSelection();
    final focus = FocusNode();
    final textFocus = FocusNode();
    final editor = TextEditingController(text: 'search');
    addTearDown(focus.dispose);
    addTearDown(textFocus.dispose);
    addTearDown(editor.dispose);
    var deletions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopCardSelectionRegion(
            focusNode: focus,
            selection: selection,
            ids: const ['a', 'b', 'c'],
            onChanged: () {},
            onDelete: () => deletions++,
            child: TextField(controller: editor, focusNode: textFocus),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selection.selected, {'a', 'b', 'c'});
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(deletions, 1);
    textFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(editor.selection.baseOffset, 0);
    expect(editor.selection.extentOffset, 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(editor.text, isEmpty);
    expect(deletions, 1);
    expect(selection.selected, {'a', 'b', 'c'});
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(selection.selected, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(deletions, 1);
  });
}
