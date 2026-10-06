import 'package:tide/storage/ledger_key.dart';

/// An in-memory [SecretStore] for host tests.
class FakeSecretStore implements SecretStore {
  FakeSecretStore([Map<String, String>? values]) : values = {...?values};

  final Map<String, String> values;

  /// When set, every call throws this.
  Object? failWith;

  int reads = 0;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read(String name) async {
    if (failWith != null) throw failWith!;
    reads++;
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async {
    if (failWith != null) throw failWith!;
    writes++;
    values[name] = value;
  }

  @override
  Future<void> delete(String name) async {
    if (failWith != null) throw failWith!;
    deletes++;
    values.remove(name);
  }
}
