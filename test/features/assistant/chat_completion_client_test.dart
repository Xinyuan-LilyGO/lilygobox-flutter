/*
 * @Description: 验证 OpenAI 兼容聊天请求与设置工具调用解析。
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
  for (final streamed in [true, false]) {
    test('Responses cache usage preserves reported zero, hits and missing counts (stream=$streamed)', () async {
      for (final cached in [0, 120000, null]) {
        final client = ChatCompletionClient(client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(body['instructions'], 'Stable');
          expect((body['input'] as List).map((row) => row['content']), ['Earlier', 'Changing', 'Now']);
          final response = {
            'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Answer'}]}],
            'usage': {'input_tokens': 182198, 'output_tokens': 7,
              if (cached != null) 'input_tokens_details': {'cached_tokens': cached},
            },
          };
          return http.Response(streamed ? 'data: ${jsonEncode({'type':'response.completed','response':response})}\n\ndata: [DONE]\n\n' : jsonEncode(response), 200);
        }));
        addTearDown(client.close);
        final completion = await client.complete(configuration: const AiServiceConfiguration(protocol: AiApiProtocol.openAiResponses, baseUrl: 'https://gateway.test/v1', model: 'gpt-6.1-sol'), apiKey: 'test', tools: const [], messages: const [
          {'role':'system', 'content':'Stable'}, {'role':'user','content':'Earlier'}, {'role':'system', 'content':'Changing'}, {'role':'user','content':'Now'},
        ]);
        expect(completion.usage?.inputTokens, 182198);
        expect(completion.usage?.cachedTokens, cached);
        expect(completion.usage?.cacheHitRatio, cached == null ? null : cached / 182198);
      }
    });
  }

  test('DeepSeek final usage-only stream chunk supplies cached and uncached token counts', () async {
    final client = ChatCompletionClient(client: MockClient((request) async {
      expect(jsonDecode(request.body)['stream_options']['include_usage'], isTrue);
      return http.Response('data: {"choices":[{"delta":{"content":"Done"}}]}\n\ndata: {"choices":[],"usage":{"prompt_cache_hit_tokens":70,"prompt_cache_miss_tokens":30}}\n\ndata: [DONE]\n\n', 200);
    }));
    addTearDown(client.close);
    final completion = await client.complete(configuration: const AiServiceConfiguration(protocol: AiApiProtocol.openAiChatCompletions, baseUrl: 'https://gateway.test/v1', model: 'deepseek-chat'), apiKey: 'test', tools: const [], messages: const [{'role':'user','content':'Now'}]);
    expect(completion.usage?.inputTokens, 100);
    expect(completion.usage?.uncachedTokens, 30);
    expect(completion.usage?.cacheHitRatio, .7);
  });
  test('catalog cancellation finishes before response headers without closing shared transport', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final abort = Completer<void>();
    var requests = 0;
    final client = ChatCompletionClient(
      client: MockClient((request) async {
        requests++;
        if (requests == 1) {
          started.complete();
          await gate.future;
        }
        return http.Response('{"data":[{"id":"model-a"}]}', 200);
      }),
    );
    final pending = client.discoverModelCatalog(
      baseUrl: 'https://example.test/v1',
      apiKey: 'key',
      abortTrigger: abort.future,
    );
    final cancelled = expectLater(
      pending,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await started.future;
    abort.complete();
    await cancelled.timeout(const Duration(seconds: 1));
    expect(gate.isCompleted, isFalse);
    final next = await client.discoverModelCatalog(
      baseUrl: 'https://example.test/v1',
      apiKey: 'key',
    );
    expect(next.models, ['model-a']);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await client.close();
  });

  for (final protocol in AiApiProtocol.values) {
    for (final outputLimit in [null, 128]) {
      test(
        'output token limit is optional for $protocol: $outputLimit',
        () async {
          late Map<String, dynamic> body;
          final client = ChatCompletionClient(
            client: MockClient((request) async {
              body = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode(switch (protocol) {
                  AiApiProtocol.openAiResponses => {
                    'output': [
                      {
                        'type': 'message',
                        'content': [
                          {'type': 'output_text', 'text': 'Done'},
                        ],
                      },
                    ],
                  },
                  AiApiProtocol.openAiChatCompletions => {
                    'choices': [
                      {
                        'message': {'content': 'Done'},
                      },
                    ],
                  },
                  AiApiProtocol.googleGemini => {
                    'candidates': [
                      {
                        'content': {
                          'parts': [
                            {'text': 'Done'},
                          ],
                        },
                      },
                    ],
                  },
                }),
                200,
              );
            }),
          );
          addTearDown(client.close);
          await client.complete(
            configuration: AiServiceConfiguration(
              protocol: protocol,
              baseUrl: 'https://example.test/v1',
              model: 'gpt-6.1-sol',
            ),
            apiKey: 'key',
            messages: const [
              {'role': 'user', 'content': 'Hello'},
            ],
            tools: const [],
            maxTokens: outputLimit,
          );
          if (protocol == AiApiProtocol.googleGemini) {
            final config = body['generationConfig'] as Map?;
            expect(
              config?.containsKey('maxOutputTokens') ?? false,
              outputLimit != null,
            );
            if (outputLimit != null) {
              expect(config?['maxOutputTokens'], outputLimit);
            }
          } else {
            final field = protocol == AiApiProtocol.openAiResponses
                ? 'max_output_tokens'
                : 'max_tokens';
            expect(body.containsKey(field), outputLimit != null);
            if (outputLimit != null) expect(body[field], outputLimit);
          }
        },
      );
    }
  }

  test('speed tiers respect explicit catalogs and fall back when metadata is absent', () async {
    final client = ChatCompletionClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'gpt-6.1-sol',
                'service_tiers': [
                  {'id': 'priority', 'name': 'Fast'},
                  {'id': 'ultrafast', 'name': 'Ultra Fast'},
                ],
              },
              {'id': 'gpt-6-astra', 'service_tiers': []},
              {
                'id': 'custom-gpt-6.1-sol',
                'reasoning_levels': ['ultrafast'],
              },
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
    expect(
      processingSpeedsForModel(
        'gpt-6.1-sol',
        serviceTiers: catalog.serviceTiers['gpt-6.1-sol'],
      ),
      AiProcessingSpeed.values,
    );
    expect(
      processingSpeedsForModel(
        'gpt-6-astra',
        serviceTiers: catalog.serviceTiers['gpt-6-astra'],
      ),
      isEmpty,
    );
    expect(
      processingSpeedsForModel(
        'custom-gpt-6.1-sol',
        serviceTiers: catalog.serviceTiers['custom-gpt-6.1-sol'],
      ),
      contains(AiProcessingSpeed.ultrafast),
    );
    expect(
      processingSpeedParameters('gpt-6.1-sol', AiProcessingSpeed.ultrafast),
      {'service_tier': 'ultrafast'},
    );
  });
  test('processing speed matches supported model substrings only', () {
    expect(
      processingSpeedsForModel('custom-GPT-6.1-SOL-test'),
      AiProcessingSpeed.values,
    );
    expect(
      processingSpeedsForModel('gpt-6.1-terra'),
      isNot(contains(AiProcessingSpeed.ultrafast)),
    );
    expect(
      processingSpeedsForModel('gpt-6-astra'),
      contains(AiProcessingSpeed.ultrafast),
    );
    expect(
      processingSpeedsForModel('gpt-6.1-sol', responses: false),
      isNot(contains(AiProcessingSpeed.ultrafast)),
    );
    expect(
      processingSpeedsForModel('gpt-6.1-sol', serviceTiers: ['priority']),
      [AiProcessingSpeed.standard, AiProcessingSpeed.fast],
    );
    expect(processingSpeedsForModel('deepseek-flash'), isEmpty);
    expect(processingSpeedsForModel('unknown'), isEmpty);
  });
  for (final protocol in const [
    AiApiProtocol.openAiChatCompletions,
    AiApiProtocol.openAiResponses,
  ]) {
    for (final speed in AiProcessingSpeed.values) {
      test('serializes processing speed $protocol $speed', () async {
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
        for (final model in ['custom-gpt-6.1-sol-test', 'deepseek-flash']) {
          await client.complete(
            configuration: AiServiceConfiguration(
              protocol: protocol,
              baseUrl: 'https://example.test/v1',
              model: model,
              processingSpeed: speed,
            ),
            apiKey: 'key',
            messages: const [
              {'role': 'user', 'content': 'Hello'},
            ],
            tools: const [],
          );
          final expected =
              model == 'deepseek-flash' ||
                  (speed == AiProcessingSpeed.ultrafast &&
                      protocol != AiApiProtocol.openAiResponses)
              ? null
              : switch (speed) {
                  AiProcessingSpeed.standard => 'default',
                  AiProcessingSpeed.fast => 'priority',
                  AiProcessingSpeed.ultrafast => 'ultrafast',
                };
          expect(body!['service_tier'], expected);
          if (expected == null) {
            expect(body!.containsKey('service_tier'), isFalse);
          }
        }
      });
    }
  }

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
  for (final protocol in const [
    AiApiProtocol.openAiChatCompletions,
    AiApiProtocol.openAiResponses,
  ]) {
    for (final (model, effort, encodedEffort) in const [
      ('o3', null, null),
      ('o3', AiReasoningEffort.high, 'high'),
      ('gpt-6.2-astra', AiReasoningEffort.high, 'high'),
      ('gpt-6.2-sol', AiReasoningEffort.none, null),
      ('gpt-6.2-sol', AiReasoningEffort.ultra, null),
      ('auto/gpt-6.2-sol', AiReasoningEffort.ultra, 'ultra'),
    ]) {
      test(
        'serializes reasoning effort for ${protocol.name}: $model $effort',
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
              model: model,
              reasoningEffort: effort,
            ),
            apiKey: 'key',
            messages: const [
              {'role': 'user', 'content': 'Hello'},
            ],
            tools: const [],
          );
          expect(body!['model'], model);
          if (encodedEffort == null) {
            expect(body!.containsKey('reasoning'), isFalse);
            expect(body!.containsKey('reasoning_effort'), isFalse);
          } else if (protocol == AiApiProtocol.openAiResponses) {
            expect(body!['reasoning'], {'effort': encodedEffort});
            expect(body!.containsKey('reasoning_effort'), isFalse);
          } else {
            expect(body!['reasoning_effort'], encodedEffort);
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
          final gemini = protocol == AiApiProtocol.googleGemini;
          final payload = switch (protocol) {
            AiApiProtocol.openAiResponses => <String, Object?>{
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
            },
            AiApiProtocol.openAiChatCompletions => <String, Object?>{
              'choices': [
                {
                  'message': {
                    'content': 'Answer',
                    'reasoning_content': 'Think carefully.',
                  },
                },
              ],
            },
            AiApiProtocol.googleGemini => <String, Object?>{
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'thought': true, 'text': 'Think carefully.'},
                      {'text': 'Answer'},
                    ],
                  },
                },
              ],
            },
          };
          final events = switch (protocol) {
            AiApiProtocol.openAiResponses => [
              {'type': 'response.reasoning_summary_text.delta', 'delta': 'Think '},
              {
                'type': 'response.reasoning_summary_text.delta',
                'delta': 'carefully.',
              },
              {'type': 'response.output_text.delta', 'delta': 'Answer'},
              {'type': 'response.completed', 'response': payload},
            ],
            AiApiProtocol.openAiChatCompletions => [
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
            ],
            AiApiProtocol.googleGemini => [
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'thought': true, 'text': 'Think '},
                      ],
                    },
                  },
                ],
              },
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'thought': true, 'text': 'carefully.'},
                        {'text': 'Answer'},
                      ],
                    },
                  },
                ],
              },
            ],
          };
          assert(!gemini || payload.isNotEmpty || responses || true);
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

  test(
    'preserves the context limit code from a Responses failure event',
    () async {
      final client = ChatCompletionClient(
        client: MockClient(
          (_) async => http.Response(
            'event: response.failed\n'
            'data: {"type":"response.failed","response":{"error":'
            '{"code":"context_length_exceeded","message":"Input exceeds capacity"}}}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.complete(
          configuration: const AiServiceConfiguration(
            protocol: AiApiProtocol.openAiResponses,
          ),
          apiKey: 'test-key',
          messages: const [
            {'role': 'user', 'content': 'Keep working'},
          ],
          tools: const [],
        ),
        throwsA(
          isA<AiRequestException>().having(
            (error) => error.code,
            'code',
            'context_length_exceeded',
          ),
        ),
      );
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
            jsonEncode(switch (protocol) {
              AiApiProtocol.openAiResponses => {
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {'type': 'output_text', 'text': 'Image received'},
                    ],
                  },
                ],
              },
              AiApiProtocol.openAiChatCompletions => {
                'choices': [
                  {
                    'message': {'content': 'Image received'},
                  },
                ],
              },
              AiApiProtocol.googleGemini => {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Image received'},
                      ],
                    },
                  },
                ],
              },
            }),
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
      if (protocol == AiApiProtocol.googleGemini) {
        final parts = (body['contents'] as List).single['parts'] as List;
        expect(parts, [
          {'text': 'Describe this image.'},
          {
            'inlineData': {'mimeType': 'image/png', 'data': 'AQID'},
          },
        ]);
      } else {
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
      }
      await client.close();
    });
  }

  test('Google Gemini streams thoughts, tool calls, usage and discovers models', () async {
    final deltas = <String>[];
    final thoughts = <String>[];
    late http.Request captured;
    final client = ChatCompletionClient(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          expect(request.headers['x-goog-api-key'], 'gem-key');
          expect(
            request.url.toString(),
            'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000',
          );
          return http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-2.5-flash',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/embedding-001',
                  'supportedGenerationMethods': ['embedContent'],
                },
              ],
            }),
            200,
          );
        }
        captured = request;
        return http.Response(
          'data: ${jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'thought': true, 'text': 'Thinking...'},
                    {'text': 'Hello '},
                  ],
                },
              },
            ],
          })}\n\n'
          'data: ${jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'world'},
                    {
                      'functionCall': {
                        'name': 'get_time',
                        'args': {'tz': 'UTC'},
                      },
                      'thoughtSignature': 'sig-123',
                    },
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
            'usageMetadata': {
              'promptTokenCount': 12,
              'candidatesTokenCount': 5,
              'thoughtsTokenCount': 3,
              'cachedContentTokenCount': 4,
            },
          })}\n\n',
          200,
        );
      }),
    );
    addTearDown(client.close);
    final catalog = await client.discoverModelCatalog(
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      apiKey: 'gem-key',
      protocol: AiApiProtocol.googleGemini,
    );
    expect(catalog.models, ['gemini-2.5-flash']);
    expect(
      catalog.imageInputs['gemini-2.5-flash'],
      AiImageInput.supported,
    );

    final completion = await client.complete(
      configuration: const AiServiceConfiguration(
        protocol: AiApiProtocol.googleGemini,
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        model: 'gemini-2.5-flash',
        reasoningEffort: AiReasoningEffort.low,
      ),
      apiKey: 'gem-key',
      messages: const [
        {'role': 'system', 'content': 'Be concise'},
        {'role': 'user', 'content': 'Hi'},
      ],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'get_time',
            'description': 'Get current time',
            'parameters': {'type': 'object'},
          },
        },
      ],
      onTextDelta: deltas.add,
      onReasoningDelta: thoughts.add,
    );
    expect(captured.headers['x-goog-api-key'], 'gem-key');
    expect(
      captured.url.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse',
    );
    final reqBody = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(reqBody['systemInstruction'], {
      'parts': [
        {'text': 'Be concise'},
      ],
    });
    expect(reqBody['generationConfig']['thinkingConfig'], {
      'includeThoughts': true,
      'thinkingBudget': 1024,
    });
    expect(thoughts, ['Thinking...']);
    expect(deltas, ['Hello ', 'world']);
    expect(completion.text, 'Hello world');
    expect(completion.reasoning, 'Thinking...');
    expect(completion.toolCalls.single.name, 'get_time');
    expect(completion.toolCalls.single.arguments, {'tz': 'UTC'});
    expect(completion.responseItems.last['thoughtSignature'], 'sig-123');
    expect(completion.usage?.inputTokens, 12);
    expect(completion.usage?.outputTokens, 8);
    expect(completion.usage?.cachedTokens, 4);
    expect(completion.finishReason, 'stop');
  });

  test('Gemini thinking capabilities match 2.5 budget, 3/4 level, and 2.0 none', () {
    expect(
      AiReasoningCapabilities.forModel('gemini-2.5-flash').levels,
      [
        AiReasoningEffort.none,
        AiReasoningEffort.low,
        AiReasoningEffort.medium,
        AiReasoningEffort.high,
      ],
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-2.5-pro').levels,
      [
        AiReasoningEffort.low,
        AiReasoningEffort.medium,
        AiReasoningEffort.high,
      ],
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-3.5-flash').levels,
      [
        AiReasoningEffort.minimal,
        AiReasoningEffort.low,
        AiReasoningEffort.medium,
        AiReasoningEffort.high,
      ],
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-3.8-flash').levels,
      [
        AiReasoningEffort.low,
        AiReasoningEffort.medium,
        AiReasoningEffort.high,
      ],
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-3-pro-preview').levels,
      [
        AiReasoningEffort.low,
        AiReasoningEffort.high,
      ],
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-4-carbon').levels,
      [
        AiReasoningEffort.low,
        AiReasoningEffort.medium,
        AiReasoningEffort.high,
      ],
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-4-hydrogen').levels,
      [
        AiReasoningEffort.low,
        AiReasoningEffort.medium,
        AiReasoningEffort.high,
        AiReasoningEffort.xhigh,
      ],
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-3.5-flash').requestParameters(
        AiReasoningEffort.medium,
        responses: false,
        gemini: true,
      ),
      {
        'thinkingConfig': {
          'includeThoughts': true,
          'thinkingLevel': 'medium',
        },
      },
    );
    expect(
      AiReasoningCapabilities.forModel('gemini-4-hydrogen').requestParameters(
        AiReasoningEffort.xhigh,
        responses: false,
        gemini: true,
      ),
      {
        'thinkingConfig': {
          'includeThoughts': true,
          'thinkingLevel': 'xhigh',
        },
      },
    );
    expect(AiReasoningCapabilities.forModel('gemini-2.0-flash').levels, isEmpty);
  });

  test('Gemini sanitizes tool schemas and ignores OpenAI Responses history items', () async {
    late Map<String, dynamic> body;
    final client = ChatCompletionClient(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'OK'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    await client.complete(
      configuration: const AiServiceConfiguration(
        protocol: AiApiProtocol.googleGemini,
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        model: 'gemini-3.5-flash',
        reasoningEffort: AiReasoningEffort.medium,
      ),
      apiKey: 'gem-key',
      messages: const [
        {'role': 'user', 'content': 'Hi'},
        {
          'role': 'assistant',
          'content': 'Hello',
          'response_items': [
            {
              'type': 'reasoning',
              'encrypted_content': 'opaque',
              'summary': [],
            },
            {
              'type': 'message',
              'role': 'assistant',
              'content': 'Hello',
            },
          ],
        },
        {'role': 'user', 'content': 'Next'},
      ],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'search',
            'parameters': {
              r'$schema': 'https://json-schema.org/draft/2020-12/schema',
              'type': 'object',
              'additionalProperties': false,
              'properties': {
                'q': {
                  'type': 'string',
                  'additionalProperties': false,
                },
                'effort': {
                  'type': ['string', 'null'],
                },
              },
            },
          },
        },
      ],
    );
    expect(body['contents'], [
      {
        'role': 'user',
        'parts': [
          {'text': 'Hi'},
        ],
      },
      {
        'role': 'model',
        'parts': [
          {'text': 'Hello'},
        ],
      },
      {
        'role': 'user',
        'parts': [
          {'text': 'Next'},
        ],
      },
    ]);
    final decl =
        ((body['tools'] as List).single as Map)['functionDeclarations'] as List;
    expect((decl.single as Map)['parameters'], {
      'type': 'object',
      'properties': {
        'q': {'type': 'string'},
        'effort': {'type': 'string', 'nullable': true},
      },
    });
  });
}
