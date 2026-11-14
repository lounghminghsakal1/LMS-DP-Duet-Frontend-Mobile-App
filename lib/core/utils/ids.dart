import 'dart:math';

final _random = Random.secure();

/// Short random id used to de-duplicate chat messages on retry.
String randomId([int length = 20]) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(length, (_) => alphabet[_random.nextInt(alphabet.length)]).join();
}
