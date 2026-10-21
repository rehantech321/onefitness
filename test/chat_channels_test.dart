import "package:flutter_test/flutter_test.dart";

import "package:onefitness/core/utils/chat_channels.dart";

/// Chat used to offer one of three things: Email, "In App / SMS", or Both.
/// Two of those three sent a text, so choosing to use the app's own chat
/// meant agreeing to be texted — and the screen refused to open the thread
/// until a phone number had been handed over. A client who didn't have one,
/// or didn't want to share it, was pushed to Email to message their coach
/// at all.
///
/// The three are now independent. These cover the rule that matters —
/// nothing but SMS needs a phone number — and the decoding of every value
/// the column has ever held, since old rows still have to render.
void main() {
  group("the blocker that prompted this", () {
    test("in app on its own is a valid choice", () {
      expect(canSendOn({ChatChannel.inapp}), isTrue);
    });

    test("and asks for no phone number", () {
      expect(channelsNeedPhone({ChatChannel.inapp}), isFalse);
    });

    test("a new chat starts on exactly that", () {
      // The default has to be the combination that needs nothing from the
      // sender, or the first thing a client meets is the old dead end.
      expect(defaultChatChannels, {ChatChannel.inapp});
      expect(channelsNeedPhone(defaultChatChannels), isFalse);
    });

    test("in app no longer implies SMS", () {
      // The old enum welded them: `inappSms` was one option.
      expect({ChatChannel.inapp}.contains(ChatChannel.sms), isFalse);
    });

    test("email is no longer the only phone-free way to chat", () {
      final free = ChatChannel.values.where((c) => !channelsNeedPhone({c}));
      expect(free, containsAll([ChatChannel.inapp, ChatChannel.email]));
    });
  });

  group("which channels need a phone number", () {
    test("SMS does", () {
      expect(channelsNeedPhone({ChatChannel.sms}), isTrue);
    });

    test("email does not", () {
      expect(channelsNeedPhone({ChatChannel.email}), isFalse);
    });

    test("any set containing SMS does", () {
      expect(channelsNeedPhone({ChatChannel.inapp, ChatChannel.sms}), isTrue);
      expect(channelsNeedPhone(ChatChannel.values.toSet()), isTrue);
    });

    test("in app plus email does not", () {
      expect(channelsNeedPhone({ChatChannel.inapp, ChatChannel.email}), isFalse);
    });

    test("SMS is the only one that does", () {
      final needing = ChatChannel.values.where((c) => channelsNeedPhone({c}));
      expect(needing, [ChatChannel.sms]);
    });
  });

  group("toggling a chip", () {
    test("turns an unselected one on", () {
      expect(toggleChannel({ChatChannel.inapp}, ChatChannel.sms), {ChatChannel.inapp, ChatChannel.sms});
    });

    test("turns a selected one off", () {
      expect(
        toggleChannel({ChatChannel.inapp, ChatChannel.sms}, ChatChannel.sms),
        {ChatChannel.inapp},
      );
    });

    test("they combine freely — all three at once", () {
      var set = {ChatChannel.inapp};
      set = toggleChannel(set, ChatChannel.sms);
      set = toggleChannel(set, ChatChannel.email);
      expect(set, ChatChannel.values.toSet());
    });

    test("turning the last one off does nothing", () {
      // A message has to go somewhere; an empty set is unsendable.
      expect(toggleChannel({ChatChannel.sms}, ChatChannel.sms), {ChatChannel.sms});
      expect(canSendOn(toggleChannel({ChatChannel.sms}, ChatChannel.sms)), isTrue);
    });

    test("no sequence of taps can empty it", () {
      var set = ChatChannel.values.toSet();
      for (var round = 0; round < 3; round++) {
        for (final c in ChatChannel.values) {
          set = toggleChannel(set, c);
          expect(canSendOn(set), isTrue, reason: "emptied by toggling ${c.name}");
        }
      }
    });

    test("the original set isn't mutated", () {
      final original = {ChatChannel.inapp};
      toggleChannel(original, ChatChannel.sms);
      expect(original, {ChatChannel.inapp});
    });
  });

  group("what gets stored", () {
    test("one channel is its own name", () {
      expect(encodeChannels({ChatChannel.inapp}), "inapp");
    });

    test("several are comma-joined in picker order", () {
      expect(encodeChannels({ChatChannel.email, ChatChannel.inapp}), "inapp,email");
      expect(encodeChannels(ChatChannel.values.toSet()), "inapp,sms,email");
    });

    test("the order is the same whatever order the set is built in", () {
      expect(
        encodeChannels({ChatChannel.email, ChatChannel.sms, ChatChannel.inapp}),
        encodeChannels({ChatChannel.inapp, ChatChannel.sms, ChatChannel.email}),
      );
    });

    test("an empty set falls back to the default, not an empty string", () {
      // No caller should reach it, but a row that says nothing at all
      // couldn't be read back.
      expect(encodeChannels(const {}), encodeChannels(defaultChatChannels));
    });

    test("every combination survives a round trip", () {
      for (final combo in [
        {ChatChannel.inapp},
        {ChatChannel.sms},
        {ChatChannel.email},
        {ChatChannel.inapp, ChatChannel.sms},
        {ChatChannel.inapp, ChatChannel.email},
        {ChatChannel.sms, ChatChannel.email},
        ChatChannel.values.toSet(),
      ]) {
        expect(decodeChannels(encodeChannels(combo)), combo, reason: "round trip lost $combo");
      }
    });
  });

  group("values written by older builds", () {
    test("\"inappSms\" decodes to the pair it used to mean", () {
      expect(decodeChannels("inappSms"), {ChatChannel.inapp, ChatChannel.sms});
    });

    test("\"both\" decodes to all three", () {
      // "Both" meant emailed AND texted, and the message was in the thread
      // regardless — so all three, not two.
      expect(decodeChannels("both"), ChatChannel.values.toSet());
    });

    test("\"email\" still means email", () {
      expect(decodeChannels("email"), {ChatChannel.email});
    });

    test("\"inapp\" still means in app", () {
      expect(decodeChannels("inapp"), {ChatChannel.inapp});
    });

    test("\"sms\", which the inbound functions write, still means SMS", () {
      // sms-inbound and twilio-inbound store a texted reply as "sms". Those
      // rows keep arriving, so this isn't only about history.
      expect(decodeChannels("sms"), {ChatChannel.sms});
    });

    test("a remembered \"inappSms\" preference doesn't change under the client", () {
      // Someone who had opted into texts keeps getting them after the
      // update, rather than being silently switched to in-app only.
      final restored = decodeChannels("inappSms");
      expect(restored, contains(ChatChannel.sms));
      expect(channelsNeedPhone(restored), isTrue);
    });
  });

  group("values that say nothing usable", () {
    test("null comes back empty", () {
      // Rows stored before the column existed.
      expect(decodeChannels(null), isEmpty);
    });

    test("so does blank", () {
      expect(decodeChannels(""), isEmpty);
      expect(decodeChannels("   "), isEmpty);
    });

    test("and so does something unrecognised, rather than a guess", () {
      expect(decodeChannels("carrier-pigeon"), isEmpty);
    });

    test("a list with one unknown token keeps the ones it knows", () {
      expect(decodeChannels("inapp,telegram,email"), {ChatChannel.inapp, ChatChannel.email});
    });

    test("whitespace around tokens is tolerated", () {
      expect(decodeChannels(" inapp , sms "), {ChatChannel.inapp, ChatChannel.sms});
    });

    test("a repeated token doesn't duplicate", () {
      expect(decodeChannels("sms,sms"), {ChatChannel.sms});
    });
  });

  group("the badge on a message bubble", () {
    /// What the badge shows: one icon per channel the row was sent on.
    int iconCount(String? stored) => decodeChannels(stored).length;

    test("a texted message now carries an icon", () {
      // The old badge compared against "inapp" while the enum wrote
      // "inappSms", so nothing matched and every In App / SMS message
      // showed no badge at all.
      expect(iconCount("inappSms"), 2);
    });

    test("one icon for one channel", () {
      expect(iconCount("inapp"), 1);
      expect(iconCount("email"), 1);
    });

    test("three for all three", () {
      expect(iconCount("inapp,sms,email"), 3);
    });

    test("nothing for a row with no channel, rather than a wrong icon", () {
      expect(iconCount(null), 0);
    });
  });

  group("the label on the context bar", () {
    test("names the one channel", () {
      expect(chatChannelsLabel({ChatChannel.inapp}), "In app");
    });

    test("names several in picker order", () {
      expect(chatChannelsLabel({ChatChannel.email, ChatChannel.inapp}), "In app · Email");
      expect(chatChannelsLabel(ChatChannel.values.toSet()), "In app · SMS · Email");
    });

    test("never reads as empty", () {
      expect(chatChannelsLabel(const {}), isNotEmpty);
    });

    test("every channel has a label", () {
      for (final c in ChatChannel.values) {
        expect(chatChannelLabels[c], isNotNull, reason: "${c.name} has no label");
      }
    });

    test("the picker shows every channel, each once", () {
      expect(chatChannelOrder.toSet(), ChatChannel.values.toSet());
      expect(chatChannelOrder.length, ChatChannel.values.length);
    });
  });

  group("declining the phone prompt", () {
    /// The screen's rule when SMS was asked for and the number wasn't
    /// given: drop SMS and open the thread on what's left. It used to
    /// abandon the whole setup, which is the bug.
    Set<ChatChannel> afterDeclining(Set<ChatChannel> wanted) {
      var chosen = toggleChannel(wanted, ChatChannel.sms);
      if (chosen.contains(ChatChannel.sms)) chosen = defaultChatChannels;
      return chosen;
    }

    test("the chat still opens", () {
      expect(canSendOn(afterDeclining({ChatChannel.inapp, ChatChannel.sms})), isTrue);
    });

    test("SMS is dropped and the rest kept", () {
      expect(
        afterDeclining({ChatChannel.inapp, ChatChannel.sms, ChatChannel.email}),
        {ChatChannel.inapp, ChatChannel.email},
      );
    });

    test("SMS alone falls back to in app rather than to nothing", () {
      // toggleChannel refuses to empty the set, so dropping the only
      // channel has to land somewhere deliverable.
      expect(afterDeclining({ChatChannel.sms}), {ChatChannel.inapp});
    });

    test("whatever is left never needs a phone number", () {
      for (final wanted in [
        {ChatChannel.sms},
        {ChatChannel.inapp, ChatChannel.sms},
        {ChatChannel.sms, ChatChannel.email},
        ChatChannel.values.toSet(),
      ]) {
        final left = afterDeclining(wanted);
        expect(channelsNeedPhone(left), isFalse, reason: "$wanted left $left, which still needs a number");
        expect(canSendOn(left), isTrue);
      }
    });
  });
}
