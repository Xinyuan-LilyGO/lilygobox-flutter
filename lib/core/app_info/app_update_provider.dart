import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_update_service.dart';
import 'package_info_provider.dart';

class AppUpdateProvider with ChangeNotifier {
  AppUpdateProvider(this._packageInfo) {
    unawaited(check());
  }

  final PackageInfoProvider _packageInfo;
  AppUpdate? _update;
  AppUpdateFailureKind? _failure;
  bool _checking = false;
  bool _cacheCleaned = false;

  AppUpdate? get update => _update;
  AppUpdateFailureKind? get failure => _failure;
  bool get checking => _checking;

  Future<AppUpdate?> check() async {
    if (_checking) return _update;
    _checking = true;
    _failure = null;
    notifyListeners();
    try {
      await _packageInfo.initializePackageInfo();
      if (!_cacheCleaned) {
        await const AppUpdateService().cleanInstallerCache(
          currentVersion: appReleaseVersion(_packageInfo.version),
        );
        _cacheCleaned = true;
      }
      final result = await const AppUpdateService().check(
        currentVersion: appReleaseVersion(_packageInfo.version),
      );
      _update = result;
      return result;
    } on AppUpdateException catch (error) {
      _update = null;
      _failure = error.kind;
      return null;
    } catch (_) {
      _update = null;
      _failure = AppUpdateFailureKind.unknown;
      return null;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }
}
