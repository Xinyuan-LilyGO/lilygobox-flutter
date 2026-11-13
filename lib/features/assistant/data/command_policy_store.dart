import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/command_policy.dart';

/// 只读取应用配置目录内的用户规则，不从项目或模型参数加载可执行规则。
class AiCommandPolicyStore {
  AiCommandPolicyStore({File? file}) : _file = file;
  final File? _file;
  static const maxBytes = 65536;

  File get file {
    if (_file != null) return _file;
    final env = Platform.environment;
    String? directory;
    if (Platform.isWindows) {
      directory = env['LOCALAPPDATA'];
      if (directory == null && env['USERPROFILE'] != null) {
        directory = '${env['USERPROFILE']!}/AppData/Local';
      }
      if (directory != null) directory += '/LILYGO/lilygobox';
    } else if (Platform.isMacOS) {
      if (env['HOME'] != null) {
        directory = '${env['HOME']!}/Library/Application Support/lilygobox';
      }
    } else {
      directory = env['XDG_CONFIG_HOME'];
      if (directory == null && env['HOME'] != null) {
        directory = '${env['HOME']!}/.config';
      }
      if (directory != null) directory += '/lilygobox';
    }
    if (directory == null || directory.isEmpty) {
      throw const AiCommandPolicyFailure(AiCommandPolicyProblem.invalidRules);
    }
    return File('$directory/command-rules.json');
  }

  Future<AiCommandPolicy> load() async {
    try {
      final source = file;
      final type = await FileSystemEntity.type(source.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        throw const AiCommandPolicyFailure(AiCommandPolicyProblem.invalidRules);
      }
      final bytes = await source
          .openRead(0, maxBytes + 1)
          .fold<List<int>>([], (buffer, chunk) => buffer..addAll(chunk));
      if (bytes.length > maxBytes) {
        throw const AiCommandPolicyFailure(AiCommandPolicyProblem.invalidRules);
      }
      var text = utf8.decode(bytes);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      return AiCommandPolicy.fromJson(
        jsonDecode(text),
        revision: sha256.convert(bytes).toString(),
      );
    } on FileSystemException catch (error) {
      // 只把明确的文件/目录不存在视为空规则，权限错误不能静默放行。
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) {
        return AiCommandPolicy();
      }
      throw const AiCommandPolicyFailure(AiCommandPolicyProblem.invalidRules);
    } catch (_) {
      throw const AiCommandPolicyFailure(AiCommandPolicyProblem.invalidRules);
    }
  }

  Future<AiCommandAssessment> assess(Map<String, Object?> args) async =>
      (await load()).assess(
        args['executable'] as String,
        (args['arguments'] as List).cast<String>(),
        windows: Platform.isWindows,
      );
}
