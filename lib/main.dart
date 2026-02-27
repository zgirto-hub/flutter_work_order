import 'package:flutter/material.dart';
//import 'screens/work_order_home.dart';
import 'screens/main_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rydrqsjofoulwdtwfbgv.supabase.co',
    anonKey: 'sb_publishable_smzkBX6r1G8TwlmQbhs7lw_bZgmZUC7',
  );

  runApp(const WorkOrderApp());
}

class WorkOrderApp extends StatelessWidget {
  const WorkOrderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = snapshot.data?.session;

          if (session == null) {
            return const LoginScreen();
          } else {
            return const MainScreen();
          }
        },
      ),
    );
  }
}
