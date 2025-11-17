/*
 * @Description: None
 * @Author: LILYGO_L
 * @Date: 2025-11-17 13:58:44
 * @LastEditTime: 2025-11-17 13:59:11
 * @License: GPL 3.0
 */
import 'package:flutter/material.dart';

class BoardManagerProvider extends ChangeNotifier {
  final List<String> _addedBoards = [];
  
  List<String> get addedBoards => _addedBoards;
  
  void addBoard(String boardName) {
    _addedBoards.add(boardName);
    notifyListeners();
  }
  
  void removeBoard(String boardName) {
    _addedBoards.remove(boardName);
    notifyListeners();
  }
  
  void clearBoards() {
    _addedBoards.clear();
    notifyListeners();
  }
}