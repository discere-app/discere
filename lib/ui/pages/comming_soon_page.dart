import 'dart:convert';

import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

class ComingSoonWidget extends StatelessWidget {
  final Object data;

  const ComingSoonWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    String jsonString;
    try {
      jsonString = const JsonEncoder.withIndent('  ').convert(data);
    } catch (e) {
      jsonString = '${context.loc.error}: $e';
    }
    return Scaffold(
        appBar: AppBar(
          title: Text(context.loc.commonComingSoon),
        ),
        body: (Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.construction,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 20),
                const SizedBox(height: 10),
                Text(
                  context.loc.commonComingSoon,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  jsonString,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
        )));
  }
}
