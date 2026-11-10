/*
 * @Description: 验证 OpenAI 兼容聊天请求与设置工具调用解析。
 * @Author: LILYGO_L
 * @Date: 2026-11-04 09:36:57
 * @LastEditTime: 2026-11-10 17:19:17
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lilygobox/features/assistant/data/chat_completion_client.dart';
import 'package:lilygobox/features/assistant/domain/models.dart';
import 'package:lilygobox/features/assistant/domain/reasoning.dart';

void main() {
  test(
    'model catalog uses explicit metadata and never guesses names',
    () async {
      final client = ChatCompletionClient(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'vision',
                  'input_modalities': ['text', 'image'],
                },
                {
                  'id': 'plain',
                  'architecture': {
                    'input_modalities': ['text'],
                  },
                },
                {'id': 'gpt-4o'},
                {
                  'id': 'malformed',
                  'input_modalities': ['text', 42],
                },
                {'id': 'empty', 'input_modalities': []},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(client.close);
      final catalog = await client.discoverModelCatalog(
        baseUrl: 'https://example.test/v1',
        apiKey: 'key',
      );
      expect(catalog.models, [
        'empty',
        'gpt-4o',
        'malformed',
        'plain',
        'vision',
      ]);
      expect(catalog.imageInputs, {
        'vision': AiImageInput.supported,
        'plain': AiImageInput.unsupported,
      });
    },
  );
  for (final protocol in AiApiProtocol.values) {
    for (final effort in [null, AiReasoningEffort.high]) {
      test(
        'serializes reasoning effort for ${protocol.name}: $effort',
        () async {
          Map<String, dynamic>? body;
          final client = ChatCompletionClient(
            client: MockClient((request) async {
              body = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode(
                  protocol == AiApiProtocol.openAiResponses
                      ? {
                          'output': [
                            {
                              'type': 'message',
                              'content': [
                                {'type': 'output_text', 'text': 'Done'},
                              ],
                            },
                          ],
                        }
                      : {
                          'choices': [
                            {
                              'message': {'content': 'Done'},
                            },
                          ],
                        },
                ),
                200,
              );
            }),
          );
          addTearDown(client.close);
          await client.complete(
            configuration: AiServiceConfiguration(
              protocol: protocol,
              baseUrl: 'https://example.test/v1',
              model: 'o3',
              reasoningEffort: effort,
            ),
            apiKey: 'key',
            messages: const [
              {'role': 'user', 'content': 'Hello'},
            ],
            tools: const [],
          );
          if (effort == null) {
            expect(body!.containsKey('reasoning'), isFalse);
            expect(body!.containsKey('reasoning_effort'), isFalse);
          } else if (protocol == AiApiProtocol.openAiResponses) {
            expect(body!['reasoning'], {'effort': 'high'});
            expect(body!.containsKey('reasoning_effort'), isFalse);
          } else {
            expect(body!['reasoning_effort'], 'high');
            expect(body!.containsKey('reasoning'), isFalse);
          }
        },
      );
    }
  }

  test(
    'DeepSeek thinking toggle and unsupported models use safe parameters',
    () {
      final deepSeek = AiReasoningCapabilities.forModel('deepseek-flash');
      expect(
        deepSeek.requestParameters(AiReasoningEffort.none, responses: false),
        {
          'thinking': {'type': 'disabled'},
        },
      );
      expect(
        deepSeek.requestParameters(AiReasoningEffort.max, responses: false),
        {
          'thinking': {'type': 'enabled'},
          'reasoning_effort': 'max',
        },
      );
      expect(
        deepSeek.requestParameters(AiReasoningEffort.max, responses: true),
        {
          'reasoning': {'effort': 'max'},
        },
      );
      expect(
        deepSeek.requestParameters(AiReasoningEffort.medium, responses: false),
        isEmpty,
      );
      for (final model in [
        'gpt-4o',
        'deepseek-chat',
        'deepseek-reasoner',
        'unknown-model',
        'o1-pro',
      ]) {
        final capabilities = AiReasoningCapabilities.forModel(model);
        expect(capabilities.levels, isEmpty);
        expect(
          capabilities.requestParameters(
            AiReasoningEffort.high,
            responses: false,
          ),
          isEmpty,
        );
      }
    },
  );

  for (final protocol in AiApiProtocol.values) {
    for (final streaming in [false, true]) {
      test(
        'reports reasoning separately for ${protocol.name}, streaming=$streaming',
        () async {
          final responses = protocol == AiApiProtocol.openAiResponses;
          final payload = responses
              ? <String, Object?>{
                  'output': [
                    {
                      'type': 'reasoning',
                      'summary': [
                        {'type': 'summary_text', 'text': 'Think carefully.'},
                      ],
                      'encrypted_content': 'opaque-private-data',
                    },
                    {
                      'type': 'message',
                      'content': [
                        {'type': 'output_text', 'text': 'Answer'},
                      ],
                    },
                  ],
                }
              : <String, Object?>{
                  'choices': [
                    {
                      'message': {
                        'content': 'Answer',
                        'reasoning_content': 'Think carefully.',
                      },
                    },
                  ],
                };
          final events = responses
              ? [
                  {
                    'type': 'response.reasoning_summary_text.delta',
                    'delta': 'Think ',
                  },
                  {
                    'type': 'response.reasoning_summary_text.delta',
                    'delta': 'carefully.',
                  },
                  {'type': 'response.output_text.delta', 'delta': 'Answer'},
                  {'type': 'response.completed', 'response': payload},
                ]
              : [
                  {
                    'choices': [
                      {
                        'delta': {'reasoning_content': 'Think '},
                      },
                    ],
                  },
                  {
                    'choices': [
                      {
                        'delta': {'reasoning_content': 'carefully.'},
                      },
                    ],
                  },
                  {
                    'choices': [
                      {
                        'delta': {'content': 'Answer'},
                      },
                    ],
                  },
                ];
          final client = ChatCompletionClient(
            client: MockClient(
              (_) async => http.Response(
                streaming
                    ? '${events.map((event) => 'data: ${jsonEncode(event)}\n\n').join()}data: [DONE]\n\n'
                    : jsonEncode(payload),
                200,
                headers: {
                  'content-type': streaming
                      ? 'text/event-stream'
                      : 'application/json',
                },
              ),
            ),
          );
          addTearDown(client.close);
          final reasoning = <String>[];
          final text = <String>[];
          final completion = await client.complete(
            configuration: AiServiceConfiguration(protocol: protocol),
            apiKey: 'secret',
            messages: const [],
            tools: const [],
            onTextDelta: text.add,
            onReasoningDelta: reasoning.add,
          );
          expect(reasoning.join(), 'Think carefully.');
          expect(completion.reasoning, 'Think carefully.');
          expect(text.join(), 'Answer');
          expect(reasoning.join(), isNot(contains('opaque-private-data')));
        },
      );
    }
  }

  for (final code in [400, 401, 403, 429, 503]) {
    test('retries only transient HTTP failures: $code', () async {
      var requests = 0;
      final retries = <int>[];
      final statuses = <AiResponseStatus>[];
      final client = ChatCompletionClient(
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          requests++;
          return http.Response('{"error":{"message":"Service failure"}}', code);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.complete(
          configuration: const AiServiceConfiguration(),
          apiKey: 'secret',
          messages: const [],
          tools: const [],
          onStatus: statuses.add,
          onRetry: (attempt, _) => retries.add(attempt),
        ),
        throwsA(
          isA<AiRequestException>().having(
            (error) => error.statusCode,
            'statusCode',
            code,
          ),
        ),
      );
      final transient = code == 429 || code == 503;
      expect(requests, transient ? 3 : 1);
      expect(retries, transient ? [1, 2] : isEmpty);
      expect(statuses.first, AiResponseStatus.connecting);
      expect(statuses.contains(AiResponseStatus.retrying), transient);
      expect(statuses.contains(AiResponseStatus.thinking), isFalse);
    });
  }

  test('retry recovery reports actual response phases', () async {
    var requests = 0;
    final statuses = <AiResponseStatus>[];
    final client = ChatCompletionClient(
      retryDelay: Duration.zero,
      client: MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('Gateway unavailable', 503)
            : http.Response('{"choices":[{"message":{"content":"OK"}}]}', 200);
      }),
    );
    addTearDown(client.close);
    final result = await client.complete(
      configuration: const AiServiceConfiguration(),
      apiKey: 'secret',
      messages: const [],
      tools: const [],
      onStatus: statuses.add,
    );
    expect(requests, 2);
    expect(result.text, 'OK');
    expect(
      statuses,
      containsAllInOrder([
        AiResponseStatus.connecting,
        AiResponseStatus.retrying,
        AiResponseStatus.thinking,
        AiResponseStatus.streaming,
      ]),
    );
  });

  test('stop cancels retry backoff before another request is sent', () async {
    var requests = 0;
    final abort = Completer<void>();
    final client = ChatCompletionClient(
      client: MockClient((_) async {
        requests++;
        return http.Response('Unavailable', 503);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.complete(
        configuration: const AiServiceConfiguration(),
        apiKey: 'secret',
        messages: const [],
        tools: const [],
        abortTrigger: abort.future,
        onRetry: (_, _) => abort.complete(),
      ),
      throwsA(isA<http.RequestAbortedException>()),
    );
    expect(requests, 1);
  });

  test('stream failures after output never replay the model request', () async {
    var requests = 0;
    Stream<List<int>> brokenStream() async* {
      yield utf8.encode(
        'data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n',
      );
      throw http.ClientException('Connection lost');
    }

    final client = ChatCompletionClient(
      retryDelay: Duration.zero,
      client: MockClient.streaming((_, body) async {
        await body.drain<void>();
        requests++;
        return http.StreamedResponse(brokenStream(), 200);
      }),
    );
    addTearDown(client.close);
    final deltas = <String>[];
    await expectLater(
      client.complete(
        configuration: const AiServiceConfiguration(),
        apiKey: 'secret',
        messages: const [],
        tools: const [],
        onTextDelta: deltas.add,
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(deltas, ['Partial']);
    expect(requests, 1);
  });

  test(
    'reports complete JSON responses through the text delta callback',
    () async {
      const responseText = 'A complete response returned without SSE.';
      final deltas = <String>[];
      final client = ChatCompletionClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': responseText},
                },
              ],
            }),
            200,
          ),
        ),
      );

      final completion = await client.complete(
        configuration: const AiServiceConfiguration(),
        apiKey: 'test-secret',
        messages: const [
          {'role': 'user', 'content': 'Hello'},
        ],
        tools: const [],
        onTextDelta: deltas.add,
      );

      expect(completion.text, responseText);
      expect(deltas, [responseText]);
      await client.close();
    },
  );

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

  for (final protocol in AiApiProtocol.values) {
    test('sends image content with ${protocol.name}', () async {
      late http.Request request;
      final client = ChatCompletionClient(
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode(
              protocol == AiApiProtocol.openAiResponses
                  ? {
                      'output': [
                        {
                          'type': 'message',
                          'content': [
                            {'type': 'output_text', 'text': 'Image received'},
                          ],
                        },
                      ],
                    }
                  : {
                      'choices': [
                        {
                          'message': {'content': 'Image received'},
                        },
                      ],
                    },
            ),
            200,
          );
        }),
      );
      await client.complete(
        configuration: AiServiceConfiguration(
          protocol: protocol,
          baseUrl: 'https://api.example.com/v1',
          model: 'vision-model',
        ),
        apiKey: 'test-secret',
        messages: const [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Describe this image.'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,AQID'},
              },
            ],
          },
        ],
        tools: const [],
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final userContent = protocol == AiApiProtocol.openAiResponses
          ? (body['input'] as List).single['content'] as List
          : (body['messages'] as List).single['content'] as List;
      expect(userContent, [
        {
          'type': protocol == AiApiProtocol.openAiResponses
              ? 'input_text'
              : 'text',
          'text': 'Describe this image.',
        },
        if (protocol == AiApiProtocol.openAiResponses)
          {'type': 'input_image', 'image_url': 'data:image/png;base64,AQID'}
        else
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AQID'},
          },
      ]);
      await client.close();
    });
  }
}
