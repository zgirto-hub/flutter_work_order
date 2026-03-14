import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String version = "";
  String buildNumber = "";

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    loadAppInfo();
  }

  Future<void> showResetPasswordDialog() async {
  final resetEmailController =
    TextEditingController(text: emailController.text);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Reset Password"),
        content: TextField(
          controller: resetEmailController,
          decoration: const InputDecoration(
            labelText: "Enter your email",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();

              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please enter email")),
                );
                return;
              }

              try {
                await supabase.auth.resetPasswordForEmail(email);

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.green,
                    content: Text("Password reset email sent"),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error: $e")),
                );
              }
            },
            child: const Text("Send"),
          ),
        ],
      );
    },
  );
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

  /*Future<void> signUp2() async {
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
  }*/

  Future<void> loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();

    setState(() {
      version = info.version;
      buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          Image.asset(
            'assets/images/logo.png',
            height: 120,
          ),

          const SizedBox(height: 30),

          TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: "Email",
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 15),

          TextField(
            controller: passwordController,
            decoration: const InputDecoration(
              labelText: "Password",
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),

          const SizedBox(height: 20),
          const SizedBox(height: 5),

Align(
  alignment: Alignment.centerRight,
  child: TextButton(
    onPressed: showResetPasswordDialog,
    child: const Text("Forgot Password?"),
  ),
),
const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: signIn,
              child: const Text("Login"),
            ),
          ),

          const SizedBox(height: 10),

         TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.orange,
                        content: Text("Contact Salah for new Account Creation"),
                    )
                  );
                },
                child: const Text("Create Account"),
             ),

       /*   TextButton(
  onPressed: signUp,
  child: const Text("Create Account"),
),*/
          const SizedBox(height: 40),

          Column(
            children: [
              const Text(
                "Developed by Salah © 2026",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),

              const SizedBox(height: 4),

              if (version.isNotEmpty)
                Text(
                  "Version $version (Build $buildNumber)",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),

              const SizedBox(height: 2),

              if (AppConfig.buildDate.isNotEmpty)
                Text(
                  "Build: ${AppConfig.buildDate}",
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
),
    );
  }
/*Future<void> signUp() async {
  try {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter email and password")),
      );
      return;
    }

    final res = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );

    if (res.user != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
          content: Text("Account created successfully"),
        ),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Signup error: $e")),
    );
  }
}*/

}