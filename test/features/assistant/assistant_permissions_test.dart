import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/data/assistant_tools.dart';
import 'package:lilygobox/features/assistant/domain/permissions.dart';

void main() {
  late Directory root;
  late Directory outside;
  late AssistantTools tools;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lilygobox-permissions-');
    outside = await Directory.systemTemp.createTemp('lilygobox-outside-');
    tools = AssistantTools();
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await outside.delete(recursive: true);
  });
  String path(String name) => '${root.path}${Platform.pathSeparator}$name';
  AiPermissions custom(AiFileAccess access) => AiPermissions(
    mode: AiApprovalMode.custom,
    files: access,
    folders: [root.path],
  );

  test(
    'default permits web and time but requests approval for files',
    () async {
      final file = await tools.prepare('read_file', {'path': path('a.txt')});
      expect(await tools.isAllowed(file, AiPermissions()), isFalse);
      final web = await tools.prepare('read_webpage', {
        'url': 'https://example.com',
      });
      expect(await tools.isAllowed(web, AiPermissions()), isTrue);
      expect(
        await tools.isAllowed(
          web,
          AiPermissions(mode: AiApprovalMode.custom, network: false),
        ),
        isFalse,
      );
      final time = await tools.prepare('get_current_time', {});
      expect(jsonDecode(await tools.execute(time))['local_time'], isNotEmpty);
    },
  );

  test(
    'read only grants reads in selected directory and rejects writes',
    () async {
      expect(
        await custom(
          AiFileAccess.readOnly,
        ).allowsFile(path('a.txt'), write: false),
        isTrue,
      );
      expect(
        await custom(
          AiFileAccess.readOnly,
        ).allowsFile(path('a.txt'), write: true),
        isFalse,
      );
      expect(
        await custom(
          AiFileAccess.readWrite,
        ).allowsFile('${outside.path}/a.txt', write: true),
        isFalse,
      );
      expect(
        await custom(
          AiFileAccess.readWrite,
        ).allowsFile('${root.path}/../outside.txt', write: true),
        isFalse,
      );
      expect(
        await custom(AiFileAccess.none).allowsFile(path('a.txt'), write: false),
        isFalse,
      );
    },
  );

  test('new file write and exact replacement preserve UTF-8 content', () async {
    var prepared = await tools.prepare('write_file', {
      'path': path('a.txt'),
      'content': '你好\n',
      'expected_content': null,
    });
    await tools.execute(prepared);
    prepared = await tools.prepare('write_file', {
      'path': path('a.txt'),
      'content': '更新\n',
      'expected_content': '你好\n',
    });
    await tools.execute(prepared);
    final read = await tools.prepare('read_file', {'path': path('a.txt')});
    expect(await tools.execute(read), '更新\n');
    expect(root.listSync().length, 1);
  });

  test(
    'stale or absent expected content cannot overwrite existing file',
    () async {
      await File(path('a.txt')).writeAsString('changed');
      for (final expected in [null, 'old']) {
        final tool = await tools.prepare('write_file', {
          'path': path('a.txt'),
          'content': 'replace',
          'expected_content': expected,
        });
        await expectLater(
          tools.execute(tool),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(await File(path('a.txt')).readAsString(), 'changed');
    },
  );

  test('cancelled writes have no side effects', () async {
    final tool = await tools.prepare('write_file', {
      'path': path('a.txt'),
      'content': 'new',
      'expected_content': null,
    });
    await expectLater(
      tools.execute(tool, isCancelled: () => true),
      throwsStateError,
    );
    expect(await File(path('a.txt')).exists(), isFalse);
  });

  test('repository metadata is protected even inside write scope', () async {
    await Directory(path('.git')).create();
    await expectLater(
      tools.prepare('write_file', {
        'path': path('.git/config'),
        'content': 'new',
        'expected_content': null,
      }),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('relative and unsupported tool requests are rejected', () async {
    await expectLater(
      tools.prepare('read_file', {'path': '../test.txt'}),
      throwsFormatException,
    );
    await expectLater(
      tools.prepare('run_command', {'command': 'anything'}),
      throwsFormatException,
    );
    await expectLater(
      tools.prepare('write_file', {'path': path('a.txt'), 'content': 'new'}),
      throwsFormatException,
    );
  });

  test('web tools reject insecure protocols and credentials', () async {
    for (final url in [
      'file:///etc/passwd',
      'http://example.com',
      'https://user:secret@example.com',
      'https://example.com:1234',
    ]) {
      await expectLater(
        tools.prepare('read_webpage', {'url': url}),
        throwsFormatException,
      );
    }
    final local = await tools.prepare('read_webpage', {
      'url': 'https://127.0.0.1',
    });
    await expectLater(tools.execute(local), throwsA(isA<SocketException>()));
  });

  test('listing is bounded and returns direct entries', () async {
    await Directory(path('sub')).create();
    await File(path('a.txt')).writeAsString('data');
    final tool = await tools.prepare('list_directory', {'path': root.path});
    final result = jsonDecode(await tools.execute(tool));
    expect(result['entries'], hasLength(2));
  });

  test('oversized files cannot be read', () async {
    await File(
      path('a.txt'),
    ).writeAsBytes(List.filled(AssistantTools.maxFileBytes + 1, 65));
    final tool = await tools.prepare('read_file', {'path': path('a.txt')});
    await expectLater(tools.execute(tool), throwsA(isA<FileSystemException>()));
  });

  test('Windows device paths and alternate streams are rejected', () async {
    if (!Platform.isWindows) return;
    for (final value in [
      r'\\server\share\file',
      path('NUL'),
      '${path('a.txt')}:stream',
      path('a.txt.'),
    ]) {
      await expectLater(
        tools.prepare('read_file', {'path': value}),
        throwsFormatException,
      );
    }
  });
  test(
    'directory links cannot escape authorized roots and retargeting invalidates approval',
    () async {
      final link = Link(path('linked'));
      await link.create(outside.path);
      await File('${outside.path}/a.txt').writeAsString('outside');
      expect(
        await custom(
          AiFileAccess.readWrite,
        ).allowsFile(path('linked/a.txt'), write: false),
        isFalse,
      );
      final prepared = await tools.prepare('read_file', {
        'path': path('linked/a.txt'),
      });
      await link.delete();
      await Directory(path('replacement')).create();
      await File(path('replacement/a.txt')).writeAsString('different');
      await link.create(path('replacement'));
      await expectLater(
        tools.execute(prepared),
        throwsA(isA<FileSystemException>()),
      );
      await link.delete();
    },
  );
}
