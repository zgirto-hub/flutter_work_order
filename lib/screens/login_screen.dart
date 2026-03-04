import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String version = "";
  String buildNumber = "";
  String buildDate = "";

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    loadAppInfo();
  }

  Future<void> signIn() async {
    try {
      await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> signUp() async {
    try {
      await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account created. Now login.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

 Future<void> loadAppInfo() async {
  final info = await PackageInfo.fromPlatform();

  final now = DateTime.now();

  setState(() {
    version = info.version;
    buildNumber = info.buildNumber;
    buildDate = "${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}";
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 120,
            ),

            const SizedBox(height: 20),

            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),

            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: signIn,
              child: const Text("Login"),
            ),

            const SizedBox(height: 10),

            TextButton(
              onPressed: null,
              child: const Text("Create Account"),
            ),

            const SizedBox(height: 30),

            // 👇 Footer
            Column(
  children: [
    const Text(
      "Developed by Salah © 2026",
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey,
      ),
    ),

    const SizedBox(height: 4),

    if (version.isNotEmpty)
      Text(
        "Version $version (Build $buildNumber)",
        style: const TextStyle(
          fontSize: 11,
          color: Colors.grey,
        ),
      ),

    const SizedBox(height: 2),

    if (buildDate.isNotEmpty)
      Text(
        "Build: $buildDate",
        style: const TextStyle(
          fontSize: 10,
          color: Colors.grey,
        ),
      ),
  ],
)
          ],
        ),
      ),
    );
  }
}