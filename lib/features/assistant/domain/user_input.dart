/*
 * @Description: 定义提问、选项和答案结构，校验用户回答。
 * @Author: Codex
 * @Date: 2026-11-13 16:57:31
 * @LastEditTime: 2026-11-13 16:57:31
 */

/// 提问内容来自工具参数；用户答案只由界面提交，不授予任何执行权限。
class AiUserInputOption {
  const AiUserInputOption({required this.label, required this.description});
  final String label;
  final String description;
}

class AiUserInputQuestion {
  AiUserInputQuestion({
    required this.id,
    required this.header,
    required this.question,
    required List<AiUserInputOption> options,
  }) : options = List.unmodifiable(options);
  final String id;
  final String header;
  final String question;
  final List<AiUserInputOption> options;
}

class AiUserInputRequest {
  AiUserInputRequest({
    required this.id,
    required List<AiUserInputQuestion> questions,
  }) : questions = List.unmodifiable(questions);
  final String id;
  final List<AiUserInputQuestion> questions;

  factory AiUserInputRequest.fromArguments(
    String id,
    Map<String, Object?> args,
  ) {
    String text(Object? value, int max) {
      if (value is! String || value.trim().isEmpty || value.length > max) {
        throw const FormatException('Invalid question text');
      }
      return value;
    }

    final values = args['questions'];
    if (values is! List || values.isEmpty || values.length > 3) {
      throw const FormatException('Provide one to three questions');
    }
    final ids = <String>{};
    final questions = <AiUserInputQuestion>[];
    for (final value in values) {
      if (value is! Map) throw const FormatException('Invalid question');
      final questionId = text(value['id'], 64);
      if (!ids.add(questionId)) {
        throw const FormatException('Duplicate question id');
      }
      final options = value['options'];
      if (options is! List || options.length < 2 || options.length > 3) {
        throw const FormatException('Provide two or three choices');
      }
      final choices = <AiUserInputOption>[];
      final labels = <String>{};
      for (final option in options) {
        if (option is! Map) throw const FormatException('Invalid choice');
        final label = text(option['label'], 200);
        if (!labels.add(label)) throw const FormatException('Duplicate choice');
        choices.add(
          AiUserInputOption(
            label: label,
            description: text(option['description'], 1000),
          ),
        );
      }
      questions.add(
        AiUserInputQuestion(
          id: questionId,
          header: text(value['header'], 80),
          question: text(value['question'], 2000),
          options: choices,
        ),
      );
    }
    return AiUserInputRequest(id: id, questions: questions);
  }

  Map<String, List<String>> validateAnswers(Map<String, List<String>> answers) {
    if (answers.length != questions.length ||
        questions.any((q) => !answers.containsKey(q.id))) {
      throw const FormatException('Answer every question');
    }
    return Map.unmodifiable({
      for (final q in questions)
        q.id: List<String>.unmodifiable(_validateAnswer(answers[q.id]!)),
    });
  }

  List<String> _validateAnswer(List<String> answers) {
    if (answers.isEmpty ||
        answers.length > 2 ||
        answers.any((v) => v.trim().isEmpty || v.length > 16000)) {
      throw const FormatException('Invalid answer');
    }
    return answers;
  }
}
