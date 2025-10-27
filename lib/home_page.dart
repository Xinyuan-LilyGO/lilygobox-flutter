import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme.dart';
import 'language.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = themeProvider.themeData;

    return Expanded(
      child: Container(
        color: theme.primary,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade800,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              context.l10n.appTitle,
              style: TextStyle(color: theme.textColor, fontSize: 24),
            ),
          ),
        ),
      ),
    );
  }
}
