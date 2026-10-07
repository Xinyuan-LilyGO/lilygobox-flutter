/*
 * @Description: 验证托盘菜单复用样式、双向悬停渐变、重复打开及操作回调。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 01:10:00
 * @LastEditTime: 2026-10-04 01:57:39
 * @License: GPL 3.0
 */

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilygobox/app/tray/menu_app.dart';
import 'package:lilygobox/core/theme/provider.dart';
import 'package:lilygobox/core/widgets/menu_item_surface.dart';
import 'package:lilygobox/core/widgets/popup_menu_surface.dart';
import 'package:lilygobox/core/widgets/popup_menu_transition.dart';

void main() {
  testWidgets(
    'tray menu fades on hover and exit, reopens and invokes actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(182, 107));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final calls = <String>[];
      final fadeRequests = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        TrayMenuApp.channel,
        (call) async {
          calls.add(call.method);
          if (call.method == 'painted') {
            fadeRequests.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          TrayMenuApp.channel,
          null,
        ),
      );
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: const TrayMenuApp()),
      );
      await tester.pumpAndSettle();
      expect(calls, ['ready']);

      Future<void> event(
        String name, [
        Map<String, Object>? args,
        bool settle = true,
      ]) async {
        final done = Completer<void>();
        unawaited(
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'lilygobox/tray_menu',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(name, args),
            ),
            (_) => done.complete(),
          ),
        );
        await tester.pump();
        if (settle) await tester.pumpAndSettle();
        await done.future;
      }

      final themes = ThemeProvider();
      addTearDown(themes.dispose);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(-10, -10));
      addTearDown(mouse.removePointer);

      await event('prepare', {
        'theme': 'dark',
        'show': '显示窗口',
        'exit': '退出',
        'reduceMotion': false,
      });
      expect(find.byType(MenuItemSurface), findsNWidgets(2));
      expect(calls, ['ready']); // 预热绘制不会通知原生窗口弹出。
      // 原来的不透明 Scaffold 和整数窗口裁剪会破坏这些半透明圆角像素。
      for (final scale in [1.0, 1.25, 1.5]) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final alpha = (await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: scale);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int at(double x, double y) => data.getUint8(
            ((y * scale).floor() * image.width + (x * scale).floor()) * 4 + 3,
          );
          final result = [
            at(16, 16),
            at(165, 16),
            at(16, 90),
            at(165, 90),
            at(90, 55),
          ];
          // 贴边阴影应在卡片外约 9 像素处消退，而不是形成大片灰色光晕。
          for (final value in [at(7, 53), at(174, 53), at(90, 7), at(90, 99)]) {
            expect(value, lessThanOrEqualTo(1));
          }
          // 窗口四边应已淡到透明，防止阴影被裁出可见的矩形边界。
          for (var x = 0; x < image.width; x++) {
            expect(data.getUint8(x * 4 + 3), lessThanOrEqualTo(1));
            expect(
              data.getUint8(((image.height - 1) * image.width + x) * 4 + 3),
              lessThanOrEqualTo(1),
            );
          }
          for (var y = 0; y < image.height; y++) {
            expect(
              data.getUint8(y * image.width * 4 + 3),
              lessThanOrEqualTo(1),
            );
            expect(
              data.getUint8((y * image.width + image.width - 1) * 4 + 3),
              lessThanOrEqualTo(1),
            );
          }
          image.dispose();
          return result;
        }))!;
        for (final corner in alpha.take(4)) {
          expect(corner, lessThan(100));
        }
        expect(alpha.last, 255);
      }
      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();
      expect(calls, ['ready']);

      for (final type in ThemeType.values) {
        themes.setTheme(type);
        final theme = themes.themeData;
        await event('present', {
          'theme': type.name,
          'show': '显示窗口',
          'exit': '退出',
          'reduceMotion': false,
        }, false);
        expect(fadeRequests.last['fadeDurationMs'], 150);
        expect(fadeRequests.last['reduceMotion'], false);
        expect(find.byType(Opacity), findsNothing);
        expect(find.byType(PopupMenuTransition), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final item = find.byType(MenuItemSurface).first;
        Color background() =>
            (tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: item,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration)
                .color!;
        final idle = background();
        final hover = tester.widget<MenuItemSurface>(item).hoverColor!;
        expect(idle, PopupMenuSurface.backgroundColorFor(theme));
        expect(tester.getSize(item).height, 28);
        expect(tester.widget<Icon>(find.byType(Icon).first).fill, 1);
        await mouse.moveTo(tester.getCenter(item));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        expect(background(), Color.lerp(idle, hover, .5));
        await tester.pumpAndSettle();
        expect(background(), hover);
        await mouse.moveTo(const Offset(-10, -10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        expect(background(), Color.lerp(hover, idle, .5));
        await tester.pumpAndSettle();
        expect(background(), idle);
        await tester.tap(find.text('显示窗口'));
        await tester.pumpAndSettle();
        expect(calls.last, 'show');
        await event('dismiss');
        expect(find.byType(MenuItemSurface), findsNWidgets(2));
      }
      // 包含原地右键展开后的鼠标位置（卡片左下方边缘），无需移出整块阴影。
      for (final point in [
        const Offset(16, 91),
        const Offset(2, 50),
        const Offset(180, 50),
        const Offset(90, 2),
        const Offset(90, 105),
        const Offset(16, 16),
        const Offset(165, 16),
        const Offset(16, 90),
        const Offset(165, 90),
      ]) {
        await event('present', {
          'theme': 'dark',
          'show': '显示窗口',
          'exit': '退出',
          'reduceMotion': false,
        });
        final countBefore = calls.length;
        // 卡片内部的分隔线不应被误判成菜单外部。
        await tester.tapAt(const Offset(90, 53));
        await tester.pumpAndSettle();
        expect(calls.length, countBefore);
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(calls.sublist(countBefore), ['dismiss']);
      }
      await event('present', {
        'theme': 'dark',
        'show': 'Show window',
        'exit': 'Exit',
        'reduceMotion': true,
      });
      expect(find.text('Exit'), findsOneWidget);
      expect(fadeRequests.last['fadeDurationMs'], 150);
      expect(fadeRequests.last['reduceMotion'], true);
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      expect(calls.last, 'exit');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(calls.last, 'dismiss');
      for (var i = 0; i < 20; i++) {
        final request = 1000 + i * 3;
        await event('present', {
          'requestId': request,
          'theme': 'dark',
          'show': '显示窗口',
          'exit': '退出',
          'reduceMotion': false,
        });
        await event('dismiss', {'requestId': request + 1});
        await event('present', {
          'requestId': request + 2,
          'theme': 'dark',
          'show': '显示窗口',
          'exit': '退出',
          'reduceMotion': false,
        });
        // 上一轮关闭消息迟到时，不应关闭新一轮菜单。
        await event('dismiss', {'requestId': request + 1});
        expect(fadeRequests.last['requestId'], request + 2);
        await tester.tapAt(const Offset(16, 91));
        await tester.pumpAndSettle();
        expect(calls.last, 'dismiss');
      }
      expect(tester.takeException(), isNull);
    },
  );
}
