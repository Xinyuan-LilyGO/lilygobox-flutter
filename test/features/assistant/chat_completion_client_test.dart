/*
 * @Description: 验证 OpenAI 兼容聊天请求与设置工具调用解析。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-04 14:52:13
 * @License: GPL 3.0
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/features/assistant/data/chat_completion_client.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';

void main() {
  test('pauses and resumes reading assistant text deltas', () async {
    final responseStream = StreamController<List<int>>();
    final firstDelta = Completer<void>();
    final secondDelta = Completer<void>();
    final deltas = <String>[];
    final client = ChatCompletionClient(
      client: MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(responseStream.stream, 200);
      }),
    );
    final completionRequest = client.complete(
      configuration: const AiServiceConfiguration(),
      apiKey: 'test-secret',
      messages: const [
        {'role': 'user', 'content': 'Continue after pausing'},
      ],
      tools: const [],
      onTextDelta: (delta) {
        deltas.add(delta);
        if (delta == 'first') firstDelta.complete();
        if (delta == 'second') secondDelta.complete();
      },
    );

    responseStream.add(
      utf8.encode('data: {"choices":[{"delta":{"content":"first"}}]}\n\n'),
    );
    await firstDelta.future;
    client.pauseResponse();
    responseStream.add(
      utf8.encode('data: {"choices":[{"delta":{"content":"second"}}]}\n\n'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(deltas, ['first']);

    client.resumeResponse();
    await secondDelta.future;
    responseStream.add(utf8.encode('data: [DONE]\n\n'));
    await responseStream.close();
    final completion = await completionRequest;

    expect(deltas, ['first', 'second']);
    expect(completion.text, 'firstsecond');
    await client.close();
  });

  test('streams assistant text deltas and requests server streaming', () async {
    late http.Request request;
    final deltas = <String>[];
    final client = ChatCompletionClient(
      client: MockClient.streaming((incoming, body) async {
        request = http.Request(incoming.method, incoming.url)
          ..headers.addAll(incoming.headers)
          ..bodyBytes = await body.toBytes();
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n',
            ),
            utf8.encode(
              'data: {"choices":[{"delta":{"content":" world"}}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    final completion = await client.complete(
      configuration: const AiServiceConfiguration(),
      apiKey: 'test-secret',
      messages: const [
        {'role': 'user', 'content': 'Say hello'},
      ],
      tools: const [],
      onTextDelta: deltas.add,
    );

    expect(jsonDecode(request.body)['stream'], isTrue);
    expect(deltas, ['Hello', ' world']);
    expect(completion.text, 'Hello world');
    await client.close();
  });

  test('posts compatible chat completions and parses tool calls', () async {
    late http.Request request;
    final client = ChatCompletionClient(
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call-1',
                      'type': 'function',
                      'function': {
                        'name': 'set_theme',
                        'arguments': '{"theme":"light"}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final completion = await client.complete(
      configuration: const AiServiceConfiguration(
        baseUrl: 'https://api.deepseek.com/',
        model: 'deepseek-chat',
      ),
      apiKey: 'test-secret',
      messages: const [
        {'role': 'user', 'content': 'Use the light theme'},
      ],
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'set_theme'},
        },
      ],
    );

    expect(request.method, 'POST');
    expect(request.url.path, '/chat/completions');
    expect(request.headers['authorization'], 'Bearer test-secret');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-chat');
    expect((body['messages'] as List).length, 1);
    expect(completion.text, isEmpty);
    expect(completion.toolCalls, hasLength(1));
    expect(completion.toolCalls.single.name, 'set_theme');
    expect(completion.toolCalls.single.arguments, {'theme': 'light'});
    await client.close();
  });

  test(
    'posts Responses API input and parses text and function calls',
    () async {
      late http.Request request;
      final client = ChatCompletionClient(
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {'type': 'output_text', 'text': 'I can change that.'},
                  ],
                },
                {
                  'type': 'function_call',
                  'call_id': 'call-responses-1',
                  'name': 'set_theme',
                  'arguments': '{"theme":"light"}',
                },
              ],
            }),
            200,
          );
        }),
      );

      final completion = await client.complete(
        configuration: const AiServiceConfiguration(
          protocol: AiApiProtocol.openAiResponses,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4.1-mini',
        ),
        apiKey: 'test-secret',
        messages: const [
          {'role': 'system', 'content': 'You are a helpful assistant.'},
          {'role': 'user', 'content': 'Change the theme.'},
          {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call-prior',
                'type': 'function',
                'function': {
                  'name': 'set_theme',
                  'arguments': '{"theme":"light"}',
                },
              },
            ],
          },
          {
            'role': 'tool',
            'tool_call_id': 'call-prior',
            'content': 'Theme changed.',
          },
        ],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'set_theme',
              'description': 'Change theme.',
              'parameters': {'type': 'object'},
            },
          },
        ],
      );

      expect(request.method, 'POST');
      expect(request.url.path, '/v1/responses');
      expect(request.headers['authorization'], 'Bearer test-secret');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4.1-mini');
      expect(body['instructions'], 'You are a helpful assistant.');
      expect(body['input'], [
        {'role': 'user', 'content': 'Change the theme.'},
        {
          'type': 'function_call',
          'call_id': 'call-prior',
          'name': 'set_theme',
          'arguments': '{"theme":"light"}',
        },
        {
          'type': 'function_call_output',
          'call_id': 'call-prior',
          'output': 'Theme changed.',
        },
      ]);
      expect(body['tools'], [
        {
          'type': 'function',
          'name': 'set_theme',
          'description': 'Change theme.',
          'parameters': {'type': 'object'},
          'strict': false,
        },
      ]);
      expect(completion.text, 'I can change that.');
      expect(completion.toolCalls.single.id, 'call-responses-1');
      expect(completion.toolCalls.single.arguments, {'theme': 'light'});
      await client.complete(
        configuration: const AiServiceConfiguration(
          protocol: AiApiProtocol.openAiResponses,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4.1-mini',
        ),
        apiKey: 'test-secret',
        messages: [
          {'role': 'assistant', 'response_items': completion.responseItems},
          {
            'role': 'tool',
            'tool_call_id': 'call-responses-1',
            'content': 'Theme changed.',
          },
        ],
        tools: const [],
      );
      final followup = jsonDecode(request.body) as Map<String, dynamic>;
      expect((followup['input'] as List).take(2), completion.responseItems);
      await client.close();
    },
  );

  test('surfaces provider error details', () async {
    final client = ChatCompletionClient(
      client: MockClient(
        (_) async =>
            http.Response('{"error":{"message":"Invalid API key"}}', 401),
      ),
    );

    await expectLater(
      client.complete(
        configuration: const AiServiceConfiguration(),
        apiKey: 'invalid',
        messages: const [],
        tools: const [],
      ),
      throwsA(
        isA<AiRequestException>().having(
          (error) => error.message,
          'message',
          'Invalid API key',
        ),
      ),
    );
    await client.close();
  });
}
