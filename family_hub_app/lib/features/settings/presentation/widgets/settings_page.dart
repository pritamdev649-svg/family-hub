import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// Chrome shared by the pushed settings screens (language, appearance,
/// location, privacy, password, about, profile): a plain canvas-coloured
/// app bar with a bold title (docs/12-DESIGN_LANGUAGE.md §3b — never a
/// coloured app bar; the status bar stays transparent over it) and a body
/// capped to the content width.
///
/// The body is edge to edge at the bottom: scroll views inside should use
/// [SettingsListView] (or [settingsListPadding]) so their last item clears
/// the gesture bar / bottom safe area.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        top: false,
        // The list pads itself for the bottom inset so it can scroll
        // behind the gesture bar.
        bottom: false,
        child: ResponsiveCenter(child: child),
      ),
    );
  }
}

/// Screen padding plus the bottom safe-area inset (docs/12 §3b: scroll
/// views with explicit padding add `MediaQuery.paddingOf(context).bottom`).
EdgeInsets settingsListPadding(BuildContext context) => EdgeInsets.fromLTRB(
  AppSpacing.lg,
  AppSpacing.lg,
  AppSpacing.lg,
  AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
);

/// The scrolling body of a settings screen: [children] with the standard
/// screen padding (see [settingsListPadding]).
class SettingsListView extends StatelessWidget {
  const SettingsListView({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: settingsListPadding(context), children: children);
  }
}
