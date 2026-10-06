/// The database key and where it is kept.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The few operations Tide needs from the platform's secure key storage.
/// The real one is [PlatformSecretStore]; tests supply their own.
abstract interface class SecretStore {
  /// The value saved under [name], or null when there is none.
  Future<String?> read(String name);

  /// Saves [value] under [name], replacing any earlier value.
  Future<void> write(String name, String value);

  /// Removes the value saved under [name], if any.
  Future<void> delete(String name);
}

/// [SecretStore] over `flutter_secure_storage`: the Android Keystore and the
/// iOS Keychain.
class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore([this._storage = defaultStorage]);

  /// The settings Tide uses.
  ///
  /// Android: the plugin's default is to wipe everything it holds when a
  /// value fails to decrypt. That would silently destroy the only key to the
  /// ledger after a passing Keystore fault, so it is turned off and the fault
  /// is reported instead.
  ///
  /// iOS: the key is readable after the first unlock and never leaves the
  /// device, so it is not carried in a backup or by iCloud Keychain. (Written
  /// but not run: iOS cannot be built on the development machine.)
  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String value) =>
      _storage.write(key: name, value: value);

  @override
  Future<void> delete(String name) => _storage.delete(key: name);
}

/// The stored key is not 64 hex digits. The message never includes it.
class LedgerKeyMalformed implements Exception {
  const LedgerKeyMalformed();

  @override
  String toString() => 'LedgerKeyMalformed: the stored ledger key is not valid';
}

/// Reads and creates the 32-byte key that encrypts the ledger.
///
/// The key lives only in the [SecretStore], as 64 hex digits. Nothing here
/// logs it or puts it in an error message.
class LedgerKeyVault {
  LedgerKeyVault(this._secrets, {Random? random, this.name = defaultName})
    : _random = random ?? Random.secure();

  /// The name the key is saved under.
  static const String defaultName = 'tide.ledger.key.v1';

  final SecretStore _secrets;
  final Random _random;
  final String name;

  /// The existing key, or null when none has been created. Throws
  /// [LedgerKeyMalformed] when something else is stored under the name.
  Future<Uint8List?> read() async {
    final stored = await _secrets.read(name);
    if (stored == null) return null;
    return _decode(stored);
  }

  /// Makes a new random key, saves it, and returns it once it reads back the
  /// same. Replaces any earlier key, so call it only when there is no
  /// database for an earlier key to open.
  Future<Uint8List> create() async {
    final key = Uint8List(32);
    for (var i = 0; i < key.length; i++) {
      key[i] = _random.nextInt(256);
    }
    await _secrets.write(name, _encode(key));
    final readBack = await _secrets.read(name);
    if (readBack == null || readBack != _encode(key)) {
      throw StateError('The ledger key could not be saved');
    }
    return key;
  }

  /// The existing key, or a newly created one when there is none.
  Future<Uint8List> readOrCreate() async => await read() ?? await create();

  static String _encode(Uint8List key) {
    final buffer = StringBuffer();
    for (final byte in key) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  static Uint8List _decode(String stored) {
    if (!_hex64.hasMatch(stored)) throw const LedgerKeyMalformed();
    final key = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      key[i] = int.parse(stored.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return key;
  }
}
