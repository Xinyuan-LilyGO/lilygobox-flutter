import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/features/assistant/domain/user_input.dart';

Map<String, Object?> questionArguments({String id = 'format'}) => {
  'questions': [
    {
      'id': id,
      'header': 'Format',
      'question': 'Which format should be used?',
      'options': [
        {'label': 'JSON', 'description': 'Machine readable'},
        {'label': 'Text', 'description': 'Human readable'},
      ],
    },
  ],
};

void main() {
  group('AiUserInputRequest', () {
    test('should accept a custom answer and retain an immutable snapshot', () {
      final request = AiUserInputRequest.fromArguments(
        'call',
        questionArguments(),
      );
      final original = ['Use CSV instead'];
      final answer = request.validateAnswers({'format': original});
      original[0] = 'changed';
      expect(answer['format'], ['Use CSV instead']);
      expect(() => answer['format']!.add('changed'), throwsUnsupportedError);
      expect(() => request.questions.clear(), throwsUnsupportedError);
      expect(
        () => request.questions.first.options.clear(),
        throwsUnsupportedError,
      );
    });

    test('should require an answer for every exact question id', () {
      final request = AiUserInputRequest.fromArguments(
        'call',
        questionArguments(),
      );
      for (final answers in <Map<String, List<String>>>[
        {},
        {
          'other': ['JSON'],
        },
        {
          'format': ['JSON'],
          'extra': ['value'],
        },
        {'format': []},
        {
          'format': ['  '],
        },
        {
          'format': ['one', 'two', 'three'],
        },
      ]) {
        expect(() => request.validateAnswers(answers), throwsFormatException);
      }
      expect(
        request.validateAnswers({
          'format': ['JSON', 'Keep Unicode'],
        }),
        {
          'format': ['JSON', 'Keep Unicode'],
        },
      );
    });

    test(
      'should reject malformed questions before opening a pending request',
      () {
        final valid = questionArguments()['questions'] as List;
        for (final arguments in <Map<String, Object?>>[
          {'questions': []},
          {
            'questions': [valid.first, valid.first],
          },
          {'questions': List.filled(4, valid.first)},
          {
            'questions': [
              {...valid.first as Map, 'id': ''},
            ],
          },
          {
            'questions': [
              {...valid.first as Map, 'options': []},
            ],
          },
          {
            'questions': [
              {
                ...valid.first as Map,
                'options': [
                  {'label': 'Same', 'description': 'A'},
                  {'label': 'Same', 'description': 'B'},
                ],
              },
            ],
          },
        ]) {
          expect(
            () => AiUserInputRequest.fromArguments('call', arguments),
            throwsFormatException,
          );
        }
      },
    );
  });
}
