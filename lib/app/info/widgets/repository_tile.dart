import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RepositoryTile extends StatelessWidget {
  const RepositoryTile({
    super.key,
    required this.title,
    required this.description,
    required this.url,
  });

  final String title;
  final String description;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.code),
      title: Text(title),
      subtitle: Text(description),
      trailing: Tooltip(
        message: context.loc.aboutOpenLinkTooltip,
        child: const Icon(Icons.open_in_new),
      ),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}
