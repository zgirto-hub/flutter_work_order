import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final oldController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();

  String message = "";
  bool loading = false;

Future<void> changePassword() async {
  setState(() {
    loading = true;
    message = "";
  });

  if (newController.text != confirmController.text) {
    setState(() {
      message = "Passwords do not match";
      loading = false;
    });
    return;
  }

  try {

    await Supabase.instance.client.auth.updateUser(
      UserAttributes(
        password: newController.text,
      ),
    );

    setState(() {
      message = "Password changed successfully";
      loading = false;
    });

  } catch (e) {
    setState(() {
      message = "Failed to update password";
      loading = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Change Password"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: oldController,
            obscureText: true,
            decoration: const InputDecoration(labelText: "Old Password"),
          ),
          TextField(
            controller: newController,
            obscureText: true,
            decoration: const InputDecoration(labelText: "New Password"),
          ),
          TextField(
            controller: confirmController,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: "Confirm Password"),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(color: Colors.red),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: loading ? null : changePassword,
          child: const Text("Update"),
        ),
      ],
    );
  }
}