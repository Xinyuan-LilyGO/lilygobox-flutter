import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String newMemoryId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String memoryContentHash(String content) => sha256
    .convert(utf8.encode(content.replaceAll('\r\n', '\n').trim()))
    .toString();

enum MemoryResolution { skip, keepBoth, replace }

class MemoryImportItem {
  MemoryImportItem({
    required this.incoming,
    required this.target,
    this.existing,
    this.incomingPrevious,
    this.duplicate = false,
  }) : content = incoming['content'] as String,
       resolution = duplicate || incomingPrevious != null
           ? MemoryResolution.skip
           : existing == null
           ? MemoryResolution.keepBoth
           : MemoryResolution.skip;
  final Map<String, Object?> incoming;
  final String target;
  final Map<String, Object?>? existing;
  final Map<String, Object?>? incomingPrevious;
  final bool duplicate;
  String content;
  MemoryResolution resolution;
  bool get conflict =>
      (existing != null || incomingPrevious != null) && !duplicate;
}

List<MemoryImportItem> planMemoryImport(
  List<Map<String, Object?>> incoming,
  List<Map<String, Object?>> existing,
  String Function(Map<String, Object?>) targetFor,
) {
  final plan = <MemoryImportItem>[];
  for (final memory in incoming) {
    final content = memory['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Invalid memory content');
    }
    final hash = memoryContentHash(content);
    if (memory['hash'] != null && memory['hash'] != hash) {
      throw const FormatException('Memory hash mismatch');
    }
    final target = targetFor(memory);
    final scoped = existing.where((m) => m['owner'] == target);
    final duplicate = scoped
        .where((m) => memoryContentHash(m['content'] as String) == hash)
        .firstOrNull;
    final lineage = memory['lineage'] ?? memory['id'];
    final previous = scoped
        .where((m) => (m['lineage'] ?? m['id']) == lineage)
        .firstOrNull;
    final repeated = plan.any(
      (m) => m.target == target && memoryContentHash(m.content) == hash,
    );
    plan.add(
      MemoryImportItem(
        incoming: memory,
        target: target,
        existing: duplicate ?? previous,
        incomingPrevious: plan
            .where(
              (item) =>
                  item.target == target &&
                  (item.incoming['lineage'] ?? item.incoming['id']) == lineage,
            )
            .firstOrNull
            ?.incoming,
        duplicate: duplicate != null || repeated,
      ),
    );
  }
  return plan;
}
