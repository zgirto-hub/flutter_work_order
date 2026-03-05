import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config.dart';

class AppFooter extends StatefulWidget {
  const AppFooter({super.key});

  @override
  State<AppFooter> createState() => _AppFooterState();
}

class _AppFooterState extends State<AppFooter> {
  String version = "";
  String buildNumber = "";

  @override
  void initState() {
    super.initState();
    loadInfo();
  }

  Future<void> loadInfo() async {
    final info = await PackageInfo.fromPlatform();

    setState(() {
      version = info.version;
      buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          "Version $version (Build $buildNumber)",
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        Text(
          "Built: ${AppConfig.buildDate}",
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}