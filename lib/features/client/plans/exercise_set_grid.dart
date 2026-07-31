import "package:flutter/material.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/utils/program_utils.dart";
import "../../../data/models/client_record.dart";
import "../../../data/models/exercise_prescription.dart";

/// One set's live (unsaved) input while a session is in progress.
class SetDraft {
  SetDraft({this.reps, this.weight});
  int? reps;
  double? weight;
}

/// Mirrors ExerciseSetGrid.jsx, trimmed to the interactive logging grid
/// (name/unilateral tag, prescribed weight/time/distance/rest, notes, and
/// the sets-as-columns grid) — canonical-exercise metadata (video, cues,
/// equipment, tempo) belongs to the not-yet-built Exercise Library feature.
///
/// Built on a [Table] rather than two independent [Column]s for the label
/// strip and the value columns — Table guarantees every row lines up across
/// columns by construction, which a hand-tuned pair of Columns does not
/// (their per-row paddings drift out of sync over several rows).
class ExerciseSetGrid extends StatefulWidget {
  const ExerciseSetGrid({
    super.key,
    required this.exercise,
    required this.client,
    required this.sessionData,
    required this.onSetChange,
    required this.dayId,
  });

  final ExercisePrescription exercise;
  final ClientRecord client;
  final Map<String, SetDraft> sessionData;
  final void Function(String exerciseName, int setNum, String field, Object? value) onSetChange;
  final String? dayId;

  @override
  State<ExerciseSetGrid> createState() => _ExerciseSetGridState();
}

class _ExerciseSetGridState extends State<ExerciseSetGrid> {
  static const _unit = "lbs";
  late List<TextEditingController> _repsControllers;
  late List<TextEditingController> _weightControllers;

  @override
  void initState() {
    super.initState();
    _buildControllers();
  }

  void _buildControllers() {
    final numSets = widget.exercise.sets > 0 ? widget.exercise.sets : 3;
    _repsControllers = List.generate(numSets, (i) {
      final draft = widget.sessionData["${widget.exercise.name}__${i + 1}"];
      return TextEditingController(text: draft?.reps?.toString() ?? "");
    });
    _weightControllers = List.generate(numSets, (i) {
      final draft = widget.sessionData["${widget.exercise.name}__${i + 1}"];
      return TextEditingController(text: draft?.weight?.toString() ?? "");
    });
  }

  @override
  void dispose() {
    for (final c in _repsControllers) {
      c.dispose();
    }
    for (final c in _weightControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final numSets = exercise.sets > 0 ? exercise.sets : 3;
    final sets = List.generate(numSets, (i) => i + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (exercise.laterality == "unilateral") ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.goldDim),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  "UNILATERAL",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.gold, letterSpacing: 0.5),
                ),
              ),
            ],
          ],
        ),
        if (exercise.weight != null || exercise.time != null || exercise.distance != null || exercise.rest != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Wrap(
              spacing: 10,
              children: [
                if (exercise.weight != null)
                  Text("@ ${exercise.weight} $_unit", style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600)),
                if (exercise.time != null)
                  Text("Time: ${exercise.time}", style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600)),
                if (exercise.distance != null)
                  Text("Distance: ${exercise.distance}", style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600)),
                if (exercise.rest != null)
                  Text("Rest: ${exercise.rest}", style: const TextStyle(fontSize: 12, color: AppColors.mute, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        if (exercise.notes != null && exercise.notes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(exercise.notes!, style: const TextStyle(fontSize: 12, color: AppColors.mute, fontStyle: FontStyle.italic)),
          ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const FixedColumnWidth(74),
              for (final n in sets) n: const FixedColumnWidth(68),
            },
            children: [
              TableRow(children: [
                const SizedBox(),
                for (final n in sets)
                  Padding(
                    padding: const EdgeInsets.only(left: 5, bottom: 4),
                    child: Text(
                      "SET $n",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.mute, letterSpacing: 1),
                    ),
                  ),
              ]),
              TableRow(children: [
                const _RowLabel("Target reps"),
                for (final n in sets) _targetRepsCell(exercise, n),
              ]),
              TableRow(children: [
                const _RowLabel("Reps Cmpl."),
                for (final n in sets) _repsInputCell(exercise, n),
              ]),
              TableRow(children: [
                _RowLabel("Last Wt ($_unit)"),
                for (final n in sets) _lastWeightCell(exercise, n),
              ]),
              TableRow(children: [
                _RowLabel("Wt ($_unit)"),
                for (final n in sets) _weightInputCell(exercise, n),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cellWrap(Widget child) => Padding(padding: const EdgeInsets.only(left: 5, top: 2.5, bottom: 2.5), child: child);

  Widget _targetRepsCell(ExercisePrescription exercise, int setNum) {
    return _cellWrap(Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.07),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.19)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        exercise.reps > 0 ? "${exercise.reps}" : "—",
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gold),
      ),
    ));
  }

  Widget _repsInputCell(ExercisePrescription exercise, int setNum) {
    final draft = widget.sessionData["${exercise.name}__$setNum"];
    final reps = draft?.reps;
    final hit = reps != null && exercise.reps > 0 && reps >= exercise.reps;
    return _cellWrap(Container(
      decoration: BoxDecoration(
        color: hit ? AppColors.grn.withValues(alpha: 0.15) : AppColors.card,
        border: Border.all(color: hit ? AppColors.grn : AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: _repsControllers[setNum - 1],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: hit ? AppColors.grn : AppColors.txt),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          border: InputBorder.none,
          hintText: exercise.reps > 0 ? "${exercise.reps}" : "",
          hintStyle: const TextStyle(color: AppColors.mute),
        ),
        onChanged: (v) {
          widget.onSetChange(exercise.name, setNum, "reps", int.tryParse(v));
          setState(() {});
        },
      ),
    ));
  }

  Widget _lastWeightCell(ExercisePrescription exercise, int setNum) {
    final last = getLastSetData(widget.client, exercise.name, setNum, widget.dayId);
    final suggested = double.tryParse(exercise.weight ?? "");
    final label = last.weight > 0 ? "${_fmtNum(last.weight)}×${last.reps}" : (suggested != null ? "Sugg. ${_fmtNum(suggested)}" : "—");
    return _cellWrap(Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(8)),
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.mute)),
    ));
  }

  Widget _weightInputCell(ExercisePrescription exercise, int setNum) {
    final draft = widget.sessionData["${exercise.name}__$setNum"];
    final weight = draft?.weight;
    final last = getLastSetData(widget.client, exercise.name, setNum, widget.dayId);
    final hasPrev = last.weight > 0;
    final suggested = double.tryParse(exercise.weight ?? "");
    final entered = weight != null && weight > 0;

    Color bg = AppColors.card, border = AppColors.line, color = AppColors.txt;
    if (entered && hasPrev) {
      if (weight > last.weight) {
        bg = const Color(0x2400E676);
        border = const Color(0xFF00E676);
        color = const Color(0xFF00E676);
      } else if (weight == last.weight) {
        bg = AppColors.gold.withValues(alpha: 0.12);
        border = AppColors.gold;
        color = AppColors.gold;
      } else {
        bg = AppColors.danger.withValues(alpha: 0.12);
        border = AppColors.danger;
        color = AppColors.danger;
      }
    } else if (entered && suggested != null) {
      if (weight > suggested) {
        bg = const Color(0x2400E676);
        border = const Color(0xFF00E676);
        color = const Color(0xFF00E676);
      } else if (weight == suggested) {
        bg = AppColors.gold.withValues(alpha: 0.12);
        border = AppColors.gold;
        color = AppColors.gold;
      } else {
        bg = AppColors.danger.withValues(alpha: 0.12);
        border = AppColors.danger;
        color = AppColors.danger;
      }
    } else if (entered) {
      bg = const Color(0x2400E676);
      border = const Color(0xFF00E676);
      color = const Color(0xFF00E676);
    }

    return _cellWrap(Container(
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(8)),
      child: TextField(
        controller: _weightControllers[setNum - 1],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          border: InputBorder.none,
          hintText: last.weight > 0 ? _fmtNum(last.weight) : (suggested != null ? _fmtNum(suggested) : ""),
          hintStyle: const TextStyle(color: AppColors.mute),
        ),
        onChanged: (v) {
          widget.onSetChange(exercise.name, setNum, "weight", double.tryParse(v));
          setState(() {});
        },
      ),
    ));
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Text(text, style: const TextStyle(fontSize: 10, color: AppColors.mute)),
    );
  }
}

String _fmtNum(double n) => n % 1 == 0 ? n.toInt().toString() : n.toString();
