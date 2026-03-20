import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppShortcuts {
  static final search = LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK);
  static final newWorkOrder = LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN);
  static final refresh = LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR);
  static final showShortcuts = LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.slash);
  static final goHome = LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyH);
  static final escape = LogicalKeySet(LogicalKeyboardKey.escape);
  static final selectAll = LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA);
  static final save = LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS);

  static Map<LogicalKeySet, ShortcutDescription> getAll() {
    return {
      search: ShortcutDescription('Search', 'Open search', 'Ctrl+K'),
      newWorkOrder: ShortcutDescription('New Work Order', 'Create a new work order', 'Ctrl+N'),
      refresh: ShortcutDescription('Refresh', 'Refresh current view', 'Ctrl+R'),
      showShortcuts: ShortcutDescription('Show Shortcuts', 'Display keyboard shortcuts', 'Ctrl+/'),
      goHome: ShortcutDescription('Go to Home', 'Navigate to home screen', 'Ctrl+H'),
      escape: ShortcutDescription('Cancel', 'Close dialog or cancel action', 'Esc'),
      selectAll: ShortcutDescription('Select All', 'Select all items', 'Ctrl+A'),
      save: ShortcutDescription('Save', 'Save current work', 'Ctrl+S'),
    };
  }
}

class ShortcutDescription {
  final String name;
  final String description;
  final String keys;

  ShortcutDescription(this.name, this.description, this.keys);
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class NewWorkOrderIntent extends Intent {
  const NewWorkOrderIntent();
}

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

class GoHomeIntent extends Intent {
  const GoHomeIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class SelectAllIntent extends Intent {
  const SelectAllIntent();
}
