/*
 * @Description: 主窗口与独立托盘窗口共用的紧凑阴影，避免大范围外扩。
 * @Author: LILYGO_L
 * @Date: 2026-10-07 00:00:00
 * @LastEditTime: 2026-10-07 00:00:00
 * @License: GPL 3.0
 */

import 'package:flutter/material.dart';

/// 独立桌面窗口的贴边阴影，使用负扩展半径收紧外缘。
const appWindowShadows = <BoxShadow>[
  BoxShadow(color: Color(0x4D000000), blurRadius: 5, spreadRadius: -1),
  BoxShadow(color: Color(0x4D000000), blurRadius: 4, spreadRadius: -2),
  BoxShadow(color: Color(0x33000000), blurRadius: 3, spreadRadius: -3),
  BoxShadow(color: Color(0x33000000), blurRadius: 2, spreadRadius: -4),
  BoxShadow(color: Color(0x1A000000), blurRadius: 1, spreadRadius: -5),
];
