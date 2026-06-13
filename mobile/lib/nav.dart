import 'package:flutter/material.dart';

import 'api/models.dart';
import 'screens/detail_screen.dart';
import 'screens/editor_screen.dart';

/// One navigator key so deep widgets (e.g. a wikilink inside rendered Markdown,
/// or the floating chat panel) can route without an InheritedWidget hop.
final navigatorKey = GlobalKey<NavigatorState>();

/// Lets the shell-level chat (which lives above the Navigator, outside any
/// Scaffold) surface SnackBars.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

NavigatorState get _nav => navigatorKey.currentState!;

/// Open an entity detail by opaque id or slug — the route the API accepts for
/// `:id` (DESIGN.md). Used by wikilinks, list rows, search, timeline, backlinks.
Future<void> openEntity(String idOrSlug) =>
    _nav.push(MaterialPageRoute(builder: (_) => DetailScreen(idOrSlug: idOrSlug)));

Future<bool?> openEditor(Entity entity) => _nav.push<bool>(
      MaterialPageRoute(builder: (_) => EditorScreen(entity: entity)),
    );

Future<bool?> openNewEntity({String? type}) => _nav.push<bool>(
      MaterialPageRoute(builder: (_) => EditorScreen(createType: type)),
    );
