import 'package:duet/core/utils/format.dart';
import 'package:duet/features/library/domain/media_match.dart';
import 'package:flutter_test/flutter_test.dart';

const _theirs =
    'RADHAKRISHNA_soundtracks_11___En_Kadhal_Nee___radhakrishna_love_song(720p)_261105203112_261105203215';

MediaMatch _compare({
  String targetFp = 'aaa',
  String pickedFp = 'bbb',
  int? targetSize = 12268544,
  int pickedSize = 12268544,
  int? targetDuration = 48000,
  int? pickedDuration = 48000,
  String targetName = _theirs,
  String pickedName = 'En Kadhal Nee.mp4',
}) =>
    compareMedia(
      targetFingerprint: targetFp,
      targetSize: targetSize,
      targetDurationMs: targetDuration,
      targetName: targetName,
      pickedFingerprint: pickedFp,
      pickedSize: pickedSize,
      pickedDurationMs: pickedDuration,
      pickedName: pickedName,
    );

void main() {
  test('tidy display titles', () {
    expect(prettyTitle(_theirs), 'RADHAKRISHNA soundtracks 11 En Kadhal Nee radhakrishna love song(720p)');
    expect(prettyTitle('Our.Trip.2024'), 'Our.Trip.2024');
    expect(prettyTitle('____'), '____');
  });

  test('same fingerprint is the same file', () {
    expect(_compare(pickedFp: 'aaa').level, MatchLevel.same);
  });

  test('same size and length counts as the same file', () {
    expect(_compare(pickedName: 'totally_renamed.mp4').level, MatchLevel.likelySame);
  });

  test('same length but different size is another copy (asks first)', () {
    final match = _compare(pickedSize: 30 * 1024 * 1024, pickedDuration: 49000);
    expect(match.level, MatchLevel.differentCopy);
    expect(match.reasons.join(' '), contains('Same length'));
  });

  test('different length is not the same media', () {
    final match = _compare(pickedSize: 90 * 1024 * 1024, pickedDuration: 192000, pickedName: 'Some other movie.mkv');
    expect(match.level, MatchLevel.different);
    expect(match.reasons.join(' '), contains('Length 3:12 vs 0:48'));
    expect(match.reasons.join(' '), contains('name looks different'));
  });

  test('unknown length: a similar name means maybe another copy, otherwise different', () {
    expect(_compare(targetDuration: null, pickedSize: 1).level, MatchLevel.differentCopy);
    expect(_compare(targetDuration: null, pickedSize: 1, pickedName: 'holiday_video.mp4').level, MatchLevel.different);
  });

  test('liberal name check', () {
    expect(namesLookAlike(_theirs, 'En Kadhal Nee - RadhaKrishna Soundtracks 11 [1080p].mp4'), isTrue);
    expect(namesLookAlike('Interstellar.2014.1080p.BluRay.x264.mkv', 'interstellar (2014).mp4'), isTrue);
    expect(namesLookAlike('Interstellar.2014.mkv', 'Inception.2010.mkv'), isFalse);
    expect(namesLookAlike('VID_20261105_203112.mp4', 'IMG_1234.mp4'), isFalse);
  });
}
