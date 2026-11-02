import "package:flutter_test/flutter_test.dart";

import "package:onefitness/data/models/progress_photo.dart";

/// Who added a progress photo.
///
/// Coaches can now add photos to a client's gallery — the useful ones are
/// taken in the gym, on the coach's phone. Because it's the client's own
/// gallery, a photo they didn't take has to say so, or it reads as one they
/// took and forgot.
void main() {
  const oneByOnePngPixel =
      "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a";

  ProgressPhoto photo({String? addedBy}) => ProgressPhoto(
        id: "p1",
        date: "2026-10-30",
        img: oneByOnePngPixel,
        addedBy: addedBy,
      );

  test("a photo the client took has no one else's name on it", () {
    // Null is also what every photo taken before this feature reads back as,
    // so none of them are retroactively credited to a coach.
    expect(photo().addedBy, isNull);
  });

  test("a photo staff added carries their name", () {
    expect(photo(addedBy: "Admin").addedBy, "Admin");
    expect(photo(addedBy: "Marine Avetisyan").addedBy, "Marine Avetisyan");
  });

  test("commenting on a photo doesn't change who added it", () {
    // copyWith is how the coach's comment box saves. If it dropped addedBy,
    // leaving a note would quietly re-credit the photo to the client.
    final coachAdded = photo(addedBy: "Admin").copyWith(
      coachComment: "Good",
      coachCommentAt: "2026-11-01",
    );
    expect(coachAdded.addedBy, "Admin");
    expect(coachAdded.coachComment, "Good");

    final clientAdded = photo().copyWith(coachComment: "Nice work");
    expect(clientAdded.addedBy, isNull);
  });

  test("the image and date survive a comment too", () {
    final edited = photo(addedBy: "Admin").copyWith(coachComment: "x");
    expect(edited.img, oneByOnePngPixel);
    expect(edited.date, "2026-10-30");
    expect(edited.id, "p1");
  });

  test("bytes decode from the data URL regardless of who added it", () {
    expect(photo(addedBy: "Admin").bytes, isNotEmpty);
    expect(photo().bytes, isNotEmpty);
  });
}
