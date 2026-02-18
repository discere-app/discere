import 'package:flutter/material.dart';

class SpeciesCommonNamesWidget extends StatelessWidget {
  final List<String> commonNames;

  const SpeciesCommonNamesWidget({super.key, required this.commonNames});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ListView.builder(
        itemCount: commonNames.length,
        itemBuilder: (context, index) {
          return SelectableText(
            commonNames[index],
            style: Theme.of(context).textTheme.bodyMedium,
          );
        },
      ),
    );
  }
}
