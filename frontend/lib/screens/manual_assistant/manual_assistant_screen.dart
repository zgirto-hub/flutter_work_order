import 'package:flutter/material.dart';
import 'chat_tab.dart';
import 'manuals_tab.dart';

class ManualAssistantScreen extends StatelessWidget {
  const ManualAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manual Assistant'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chat'),
              Tab(text: 'Manuals'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ChatTab(),
            ManualsTab(),
          ],
        ),
      ),
    );
  }
}
