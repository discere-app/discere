import 'dart:convert';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

class ComingSoonPage extends StatelessWidget {
  final Object data;

  const ComingSoonPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    String jsonString;
    try {
      jsonString = const JsonEncoder.withIndent('  ').convert(data);
    } catch (e) {
      jsonString = '${context.loc.error}: $e';
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.commonComingSoon)),
      body: (Center(
        child: SingleChildScrollView(
          padding: AppSpacing.paddingS16All,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction, size: 80, color: Colors.grey.shade400),
              AppSpacing.heightS24,
              AppSpacing.heightS8,
              Text(
                context.loc.commonComingSoon,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              AppSpacing.heightS8,
              Text(
                jsonString,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.start,
              ),
            ],
          ),
        ),
      )),
    );
  }
}
