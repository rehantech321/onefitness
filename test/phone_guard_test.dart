import "package:flutter_test/flutter_test.dart";
import "package:onefitness/core/utils/phone_guard.dart";

void main() {
  test("matches the support number however it's formatted", () {
    const support = "8182237001";
    expect(isGymSupportNumber("818-223-7001", support), isTrue);
    expect(isGymSupportNumber("(818) 223 7001", support), isTrue);
    expect(isGymSupportNumber("+1 818 223 7001", support), isTrue);
  });

  test("a different number is allowed", () {
    expect(isGymSupportNumber("818-223-7002", "8182237001"), isFalse);
  });

  test("no support number set blocks nothing", () {
    expect(isGymSupportNumber("818-223-7001", ""), isFalse);
    expect(isGymSupportNumber("", ""), isFalse);
  });
}
