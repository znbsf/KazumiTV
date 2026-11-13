import 'package:hive_ce/hive.dart';

/// Fail closed on locking, permissions, I/O and corrupt frames alike. Hive's
/// automatic crash recovery can truncate a corrupt file, so disable it here.
/// Recovery requires an explicit backup/restore decision, never an empty box.
Future<Box<T>> openBoxPreservingData<T>(String name, {HiveInterface? hive}) {
  return (hive ?? Hive).openBox<T>(name, crashRecovery: false);
}
