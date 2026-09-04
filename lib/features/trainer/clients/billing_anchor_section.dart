import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/billing_anchor_history_entry.dart";
import "../../../data/models/client_info.dart";

/// Billing Cycle Anchor Date spec §3 — owner-only per-client override, with
/// a mandatory preview step before anything is actually applied ("Show the
/// owner a preview of the proration/next-charge date and amount before
/// confirming the change — this avoids surprise charges for both sides").
/// Three states: pick a day → preview (read-only, re-runnable) → confirm
/// (the only step that actually touches Stripe/the database). History is
/// always visible underneath regardless of which state the picker is in.
class BillingAnchorSection extends ConsumerStatefulWidget {
  const BillingAnchorSection({super.key, required this.info, required this.onBack, required this.onChanged});

  final ClientInfo info;
  final VoidCallback onBack;
  final ValueChanged<int> onChanged;

  @override
  ConsumerState<BillingAnchorSection> createState() => _BillingAnchorSectionState();
}

class _BillingAnchorSectionState extends ConsumerState<BillingAnchorSection> {
  late int _pickedDay = widget.info.billingAnchorDay ?? DateTime.now().day.clamp(1, 28);
  Map<String, dynamic>? _preview;
  bool _previewing = false;
  bool _applying = false;
  String? _error;
  late Future<List<BillingAnchorHistoryEntry>> _historyFuture = SupabaseService.loadBillingAnchorHistory(widget.info.id);

  Future<void> _runPreview() async {
    setState(() {
      _previewing = true;
      _error = null;
      _preview = null;
    });
    try {
      final res = await SupabaseService.previewBillingAnchorChange(clientId: widget.info.id, newAnchorDay: _pickedDay);
      if (mounted) setState(() => _preview = res);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await SupabaseService.changeBillingAnchor(clientId: widget.info.id, newAnchorDay: _pickedDay);
      widget.onChanged(_pickedDay);
      if (mounted) {
        setState(() {
          _preview = null;
          _historyFuture = SupabaseService.loadBillingAnchorHistory(widget.info.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Billing date changed to the ${ordinalDay(_pickedDay)} of the month.")),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(onBack: widget.onBack, title: "Profile"),
          const SizedBox(height: 10),
          SectionLabel("Billing Date — ${widget.info.name}"),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 14),
            child: Text(
              widget.info.billingAnchorDay != null
                  ? "Currently bills on the ${ordinalDay(widget.info.billingAnchorDay!)} of the month."
                  : "No billing date override on file — bills on whatever day they originally signed up.",
              style: const TextStyle(fontSize: 12, color: AppColors.mute),
            ),
          ),
          const Text("NEW DAY OF THE MONTH", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(28, (i) => i + 1).map((day) {
              final selected = day == _pickedDay;
              return InkWell(
                onTap: () => setState(() {
                  _pickedDay = day;
                  _preview = null;
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? AppColors.gold : AppColors.line),
                    color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
                  ),
                  child: Text("$day", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.gold : AppColors.txt)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          BtnGhost(
            full: true,
            onPressed: _previewing ? null : _runPreview,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.eye, size: 14),
                const SizedBox(width: 6),
                Text(_previewing ? "Checking…" : "Preview this change"),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFC97F7F), fontSize: 12)),
            ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            AppCard(
              borderColor: AppColors.goldDim,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("PREVIEW", style: TextStyle(fontSize: 10, color: AppColors.mute, letterSpacing: 1)),
                  const SizedBox(height: 6),
                  if (_preview!["hasActiveSubscription"] == false)
                    Text(_preview!["message"] as String? ?? "No active Stripe subscription — nothing to prorate.", style: const TextStyle(fontSize: 13))
                  else ...[
                    Builder(builder: (context) {
                      final cents = (_preview!["proratedAmountCents"] as num?)?.toInt() ?? 0;
                      final dollars = (cents / 100).toStringAsFixed(2);
                      final isCharge = cents >= 0;
                      return Text(
                        "${isCharge ? "Charges" : "Credits"} \$${dollars.replaceFirst('-', '')} today to cover the transition period.",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      );
                    }),
                    const SizedBox(height: 4),
                    Text("Next full charge: ${_preview!["nextChargeDate"]}, and every month on the ${ordinalDay(_pickedDay)} after that.", style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                  ],
                  const SizedBox(height: 12),
                  BtnGold(
                    full: true,
                    onPressed: _applying ? null : _confirm,
                    child: Text(_applying ? "Applying…" : "Confirm change"),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          const SectionLabel("Change History"),
          const SizedBox(height: 8),
          FutureBuilder<List<BillingAnchorHistoryEntry>>(
            future: _historyFuture,
            builder: (context, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator()));
              final rows = snap.data!;
              if (rows.isEmpty) return const HintBox(text: "No billing date changes on record yet.");
              return Column(
                children: rows.map((r) {
                  final cents = r.proratedAmountCents;
                  return AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${r.oldValue != null ? ordinalDay(r.oldValue!) : "(unset)"} → ${ordinalDay(r.newValue)}",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${r.changedAt}${r.changedByName != null ? " · by ${r.changedByName}" : ""}${cents != null ? " · \$${(cents / 100).toStringAsFixed(2)} prorated" : ""}",
                          style: const TextStyle(fontSize: 11, color: AppColors.mute),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// "1st", "2nd", "3rd", "4th"... — for displaying a billing_anchor_day.
String ordinalDay(int day) {
  if (day % 100 >= 11 && day % 100 <= 13) return "${day}th";
  switch (day % 10) {
    case 1:
      return "${day}st";
    case 2:
      return "${day}nd";
    case 3:
      return "${day}rd";
    default:
      return "${day}th";
  }
}
