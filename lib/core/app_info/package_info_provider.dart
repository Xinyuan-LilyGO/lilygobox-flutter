/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-03 15:05:33
 * @LastEditTime: 2025-11-17 11:27:26
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class PackageInfoProvider with ChangeNotifier {
  PackageInfo? _packageInfo;
  bool _isLoading = false;
  String? _error;

  PackageInfo? get packageInfo => _packageInfo;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // 获取包信息
  Future<void> initializePackageInfo() async {
    if (_packageInfo != null || _isLoading) return; // 避免重复初始化

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _packageInfo = await PackageInfo.fromPlatform();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  // 获取版本号
  String get version => _packageInfo?.version ?? 'Unknown';

  // 获取构建号
  String get buildNumber => _packageInfo?.buildNumber ?? 'Unknown';

  // 获取应用名称
  String get appName => _packageInfo?.appName ?? 'Unknown';

  // 获取包名
  String get packageName => _packageInfo?.packageName ?? 'Unknown';
}
