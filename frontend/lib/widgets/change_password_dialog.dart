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
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSuccess = false;

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
      _isSuccess = true;
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
            obscureText: _obscureOld,
            decoration: InputDecoration(
              labelText: "Old Password",
              suffixIcon: IconButton(
                icon: Icon(_obscureOld ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureOld = !_obscureOld),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: newController,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: "New Password",
              suffixIcon: IconButton(
                icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: "Confirm Password",
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (message.isNotEmpty)
            Text(
              message,
              style: TextStyle(color: _isSuccess ? Colors.green : Colors.red),
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