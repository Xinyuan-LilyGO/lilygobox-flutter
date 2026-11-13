import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/presentation/widgets/command_display.dart';

void main() {
  test(
    'Windows display quotes paths, empty arguments, apostrophes and scripts',
    () {
      expect(
        formatAiCommand({
          'executable': r'C:\Program Files\tool.exe',
          'arguments': [
            '--name',
            "O'Brien",
            '',
            'a b',
            r'$value',
            'a,b',
            'a&b',
          ],
        }, windows: true),
        "& 'C:\\Program Files\\tool.exe' --name 'O''Brien' '' 'a b' "
        "'\$value' 'a,b' 'a&b'",
      );
      const script = "Write-Output 'hello'\nWrite-Output done";
      expect(
        formatAiCommand({
          'executable': 'pwsh.exe',
          'arguments': ['-NoProfile', '-Command', script],
        }, windows: true),
        "pwsh.exe -NoProfile -Command 'Write-Output ''hello''\nWrite-Output done'",
      );
    },
  );
  test('POSIX display quotes shell metacharacters and backslashes', () {
    expect(
      formatAiCommand({
        'executable': '/usr/bin/tool',
        'arguments': ['a b', "O'Brien", '', r'a\b', r'$value', ';'],
      }, windows: false),
      "/usr/bin/tool 'a b' 'O'\"'\"'Brien' '' 'a\\b' '\$value' ';'",
    );
  });
  test('PowerShell display preserves smart single quotes', () {
    expect(
      formatAiCommand({
        'executable': 'tool.exe',
        'arguments': ['a\u2018b', 'a\u2019b', "a'b"],
      }, windows: true),
      "tool.exe 'a\u2018\u2018b' 'a\u2019\u2019b' 'a''b'",
    );
  });
  test('executable without arguments occurs once', () {
    expect(
      formatAiCommand({'executable': 'tool.exe'}, windows: true),
      'tool.exe',
    );
    expect(
      formatAiCommand({
        'executable': '/usr/bin/tool',
        'arguments': [],
      }, windows: false),
      '/usr/bin/tool',
    );
  });
}
