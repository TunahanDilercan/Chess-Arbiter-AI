import 'game_repository.dart';

/// Platforms without dart:io (web) have no file store.
Future<GameRepository?> createFileRepository() async => null;
