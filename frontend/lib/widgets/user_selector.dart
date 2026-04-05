import 'package:flutter/material.dart';
import '../models/user.dart';

class UserSelector extends StatefulWidget {
  final List<AppUser> users;
  final String? selectedUserId;
  final Function(AppUser) onSelected;

  const UserSelector({
    super.key,
    required this.users,
    this.selectedUserId,
    required this.onSelected,
  });

  @override
  State<UserSelector> createState() => _UserSelectorState();
}

class _UserSelectorState extends State<UserSelector> {
  String search = "";

  @override
  Widget build(BuildContext context) {
    final filtered = widget.users
        .where((e) =>
            (e.fullName ?? '').toLowerCase().contains(search.toLowerCase()) ||
            (e.email ?? '').toLowerCase().contains(search.toLowerCase()))
        .toList();

    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: SizedBox(
        height: 500,
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Text(
              "Select User",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: "Search user...",
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    search = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final user = filtered[index];
                  return ListTile(
                    title: Text(user.displayName),
                    subtitle: Text(user.email ?? ''),
                    trailing: Text(
                      user.userTypeString,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      widget.onSelected(user);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
