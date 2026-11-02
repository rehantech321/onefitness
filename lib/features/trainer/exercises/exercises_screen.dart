import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:lucide_flutter/lucide_flutter.dart";
import "../../../core/navigation/local_back_stack.dart";
import "../../../core/supabase/supabase_service.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/widgets/widgets.dart";
import "../../../data/models/exercise_def.dart";
import "../../../data/providers/trainer_providers.dart";

/// Mirrors ExercisesTab.jsx + ExerciseEditForm.jsx — the coach-editable
/// exercise library. Trimmed: no regression/progression swap-links, no
/// "used in these programs" delete guard (this trimmed build's programs
/// library is small enough that a plain confirm suffices).
class ExercisesScreen extends ConsumerStatefulWidget {
  const ExercisesScreen({super.key});

  @override
  ConsumerState<ExercisesScreen> createState() => _ExercisesScreenState();
}

class _ExercisesScreenState extends ConsumerState<ExercisesScreen> {
  final _search = TextEditingController();
  ExerciseDef? _editing;
  bool _creatingNew = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(exerciseCatalogProvider);

    if (_editing != null || _creatingNew) {
      return LocalBackScope(
        isOpen: true,
        onBack: () => setState(() {
          _editing = null;
          _creatingNew = false;
        }),
        child: _ExerciseEditForm(
          initial: _editing,
          onCancel: () => setState(() {
            _editing = null;
            _creatingNew = false;
          }),
          onSave: (ex) async {
            try {
              await SupabaseService.upsertExercise(ex);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Couldn't save — check your connection and try again.",
                    ),
                  ),
                );
              }
              return;
            }
            ref.read(exerciseCatalogProvider.notifier).upsert(ex);
            setState(() {
              _editing = null;
              _creatingNew = false;
            });
          },
          onDelete: _editing == null
              ? null
              : () async {
                  final id = _editing!.id;
                  try {
                    await SupabaseService.deleteExercise(id);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Couldn't delete — check your connection and try again.",
                          ),
                        ),
                      );
                    }
                    return;
                  }
                  ref.read(exerciseCatalogProvider.notifier).remove(id);
                  setState(() => _editing = null);
                },
        ),
      );
    }

    final q = _search.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? catalog
        : catalog
              .where(
                (e) =>
                    e.name.toLowerCase().contains(q) ||
                    e.primaryMuscle.toLowerCase().contains(q) ||
                    e.movementPattern.toLowerCase().contains(q) ||
                    e.equipment.any((eq) => eq.toLowerCase().contains(q)),
              )
              .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SectionLabel("Exercises (${catalog.length})"),
              TextButton.icon(
                onPressed: () => setState(() => _creatingNew = true),
                icon: Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: AppColors.gold,
                ),
                label: Text(
                  "New exercise",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          AppField(kind: FieldKind.search,
            controller: _search,
            placeholder: "Search name, muscle, movement, equipment…",
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          ...visible.map(
            (e) => AppCard(
              onTap: () => setState(() => _editing = e),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            Tag(text: e.primaryMuscle, gold: true),
                            Tag(text: e.movementPattern),
                            // Which exercises still need filming is the one
                            // thing a coach can't tell from this list
                            // otherwise, short of opening every one.
                            if (e.hasVideo) const Tag(text: "Video"),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 15,
                    color: AppColors.mute,
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            const HintBox(text: "No exercises match that search."),
        ],
      ),
    );
  }
}

class _ExerciseEditForm extends StatefulWidget {
  const _ExerciseEditForm({
    required this.initial,
    required this.onCancel,
    required this.onSave,
    required this.onDelete,
  });
  final ExerciseDef? initial;
  final VoidCallback onCancel;
  final ValueChanged<ExerciseDef> onSave;
  final VoidCallback? onDelete;

  @override
  State<_ExerciseEditForm> createState() => _ExerciseEditFormState();
}

class _ExerciseEditFormState extends State<_ExerciseEditForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? "");
  late String _movement =
      widget.initial?.movementPattern ?? kMovementPatterns.first;
  late String _muscle = widget.initial?.primaryMuscle ?? kMuscleGroups.first;
  // Picked from the Equipment Library rather than typed as a comma list,
  // so every exercise spells "Kettlebell" the same way and search on the
  // exercise list matches. Anything new typed here goes into the library.
  late final Set<String> _equipment = {...?widget.initial?.equipment};
  final _newEquipment = TextEditingController();
  bool _addingEquipment = false;
  late final _setup = TextEditingController(text: widget.initial?.setup ?? "");
  late final _cues = TextEditingController(text: widget.initial?.cues ?? "");
  late final _coachNotes = TextEditingController(
    text: widget.initial?.coachNotes ?? "",
  );
  late String? _videoPath = widget.initial?.videoPath;
  late String? _videoName = widget.initial?.videoName;

  /// Clips uploaded while this form has been open. Replacing one of these is
  /// safe to clean up, because no saved exercise has ever pointed at it —
  /// unlike the clip the form opened with, which stays in the bucket even if
  /// it's replaced, so that cancelling out leaves the saved exercise playable.
  final _uploadedHere = <String>{};

  /// The clip handed to [_ExerciseEditForm.onSave], if Save has been pressed.
  /// Everything else in [_uploadedHere] is abandoned when this form closes.
  String? _handedOff;

  /// An existing exercise keeps its id; a new one takes it from the name, so
  /// that a video uploaded before Save is filed under the same folder the
  /// saved exercise will have.
  String _exerciseId() =>
      widget.initial?.id ??
      _name.text.trim().toLowerCase().replaceAll(RegExp(r"\s+"), "-");

  /// Points the form at [path], cleaning up whatever it was showing if that
  /// clip was uploaded here and so was never saved anywhere.
  void _setVideo(String? path, String? name) {
    setState(() {
      final previous = _videoPath;
      _videoPath = path;
      _videoName = name;
      if (path != null) _uploadedHere.add(path);
      if (previous != null && _uploadedHere.remove(previous)) {
        SupabaseService.deleteExerciseVideo(previous).ignore();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _newEquipment.dispose();
    _setup.dispose();
    _cues.dispose();
    _coachNotes.dispose();
    // A coach who uploads a 90MB clip and then backs out has left it in the
    // bucket with nothing pointing at it. Only clips uploaded here are
    // cleaned up, and never the one just saved — so the worst this can do is
    // leave a file behind, never take away one an exercise still plays.
    for (final path in _uploadedHere) {
      if (path != _handedOff) SupabaseService.deleteExerciseVideo(path).ignore();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BackBar(
            onBack: widget.onCancel,
            title: widget.initial != null ? "Edit Exercise" : "New Exercise",
          ),
          const SizedBox(height: 14),
          FieldLabeled(
            label: "Name",
            child: AppField(kind: FieldKind.name, controller: _name),
          ),
          const SizedBox(height: 10),
          Text(
            "MOVEMENT PATTERN",
            style: TextStyle(
              fontSize: 10,
              color: AppColors.mute,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          _ChipPicker(
            value: _movement,
            options: kMovementPatterns,
            onChanged: (v) => setState(() => _movement = v),
          ),
          const SizedBox(height: 10),
          Text(
            "PRIMARY MUSCLE",
            style: TextStyle(
              fontSize: 10,
              color: AppColors.mute,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          _ChipPicker(
            value: _muscle,
            options: kMuscleGroups,
            onChanged: (v) => setState(() => _muscle = v),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Equipment",
            child: Consumer(builder: (context, ref, _) {
              final library = [...ref.watch(equipmentProvider)]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              // Anything this exercise already lists that isn't in the
              // library (older free-typed entries) still shows, selected.
              final extras = _equipment.where((e) => !library.any((l) => l.toLowerCase() == e.toLowerCase())).toList();
              Future<void> addNew() async {
                final name = _newEquipment.text.trim();
                if (name.isEmpty) return;
                final existing = library.where((l) => l.toLowerCase() == name.toLowerCase());
                final canonical = existing.isNotEmpty ? existing.first : name;
                setState(() {
                  _addingEquipment = true;
                });
                try {
                  if (existing.isEmpty) {
                    await SupabaseService.insertEquipment(canonical);
                    ref.read(equipmentProvider.notifier).add(canonical);
                  }
                  setState(() {
                    _equipment.add(canonical);
                    _newEquipment.clear();
                  });
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't add that equipment — check your connection and try again.")));
                  }
                } finally {
                  if (mounted) setState(() => _addingEquipment = false);
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (library.isEmpty && extras.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text("The Equipment Library is empty — add the first item below.", style: TextStyle(fontSize: 11, color: AppColors.mute)),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in [...library, ...extras])
                        InkWell(
                          onTap: () => setState(() {
                            if (!_equipment.remove(name)) _equipment.add(name);
                          }),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: _equipment.contains(name) ? AppColors.gold.withValues(alpha: 0.15) : AppColors.bg,
                              border: Border.all(color: _equipment.contains(name) ? AppColors.gold : AppColors.line),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _equipment.contains(name) ? AppColors.gold : AppColors.txt)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: AppField(kind: FieldKind.name, controller: _newEquipment, placeholder: "Add new equipment…")),
                      const SizedBox(width: 8),
                      BtnGhost(onPressed: _addingEquipment ? null : addNew, child: Text(_addingEquipment ? "Adding…" : "+ Add")),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text("New equipment is saved to the Equipment Library for every coach.", style: TextStyle(fontSize: 11, color: AppColors.mute, fontStyle: FontStyle.italic)),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Setup",
            child: AppField(controller: _setup),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Cues",
            child: AppField(controller: _cues),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Coach notes (internal, never shown to clients)",
            child: AppField(controller: _coachNotes),
          ),
          const SizedBox(height: 10),
          FieldLabeled(
            label: "Demo video (clients watch this while they train)",
            child: _ExerciseVideoField(
              videoPath: _videoPath,
              videoName: _videoName,
              exerciseId: _exerciseId,
              onUploaded: _setVideo,
              onRemoved: () => _setVideo(null, null),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: BtnGold(
                  onPressed: _name.text.trim().isEmpty
                      ? null
                      : () {
                          // Noted before handing over, so that closing the
                          // form doesn't clean up the clip being saved.
                          _handedOff = _videoPath;
                          widget.onSave(
                            ExerciseDef(
                              id: _exerciseId(),
                              name: _name.text.trim(),
                              movementPattern: _movement,
                              primaryMuscle: _muscle,
                              equipment: _equipment.toList(),
                              setup: _setup.text.trim().isEmpty
                                  ? null
                                  : _setup.text.trim(),
                              cues: _cues.text.trim().isEmpty
                                  ? null
                                  : _cues.text.trim(),
                              coachNotes: _coachNotes.text.trim().isEmpty
                                  ? null
                                  : _coachNotes.text.trim(),
                              videoPath: _videoPath,
                              videoName: _videoName,
                            ),
                          );
                        },
                  child: const Text("Save"),
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: widget.onCancel, child: const Text("Cancel")),
            ],
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.errorText,
              ),
              child: const Text("Delete exercise"),
            ),
          ],
        ],
      ),
    );
  }
}

/// Picks a clip, uploads it with a real progress bar, and previews whatever
/// the exercise currently has.
class _ExerciseVideoField extends StatefulWidget {
  const _ExerciseVideoField({
    required this.videoPath,
    required this.videoName,
    required this.exerciseId,
    required this.onUploaded,
    required this.onRemoved,
  });

  final String? videoPath;
  final String? videoName;

  /// Read at upload time rather than passed as a value: on a new exercise the
  /// id follows the name field, which the coach may still be typing.
  final String Function() exerciseId;

  final void Function(String path, String name) onUploaded;
  final VoidCallback onRemoved;

  @override
  State<_ExerciseVideoField> createState() => _ExerciseVideoFieldState();
}

class _ExerciseVideoFieldState extends State<_ExerciseVideoField> {
  /// Null unless an upload is in flight; otherwise 0–1.
  double? _progress;
  String? _error;

  /// What is being uploaded, named while the bar is on screen so a coach who
  /// picked the wrong take can tell before it finishes.
  String? _uploadingName;

  Future<void> _pick() async {
    if (_progress != null) return;
    setState(() => _error = null);

    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: SupabaseService.kExerciseVideoTypes.keys.toList(),
        // Streamed from the file rather than loaded: a phone recording runs
        // to tens of megabytes, and `withData` would put all of it on the
        // heap at once before a single byte went out.
        withReadStream: true,
      );
    } catch (_) {
      setState(() => _error = "Couldn't open the file picker.");
      return;
    }

    final file = result?.files.firstOrNull;
    if (file == null) return;

    final stream = file.readStream;
    if (stream == null) {
      setState(() => _error = "Couldn't read that file.");
      return;
    }
    if (file.size > SupabaseService.kExerciseVideoMaxBytes) {
      setState(
        () => _error =
            "That video is ${_mb(file.size)} — the limit is "
            "${_mb(SupabaseService.kExerciseVideoMaxBytes)}. Trim it and try again.",
      );
      return;
    }
    final contentType =
        SupabaseService.kExerciseVideoTypes[file.extension?.toLowerCase() ?? ""];
    if (contentType == null) {
      setState(() => _error = "That file type can't be uploaded.");
      return;
    }

    setState(() {
      _progress = 0;
      _uploadingName = file.name;
    });
    try {
      final path = await SupabaseService.uploadExerciseVideo(
        exerciseId: widget.exerciseId(),
        bytes: stream,
        length: file.size,
        contentType: contentType,
        onProgress: (fraction) {
          if (mounted) setState(() => _progress = fraction);
        },
      );
      if (!mounted) return;
      widget.onUploaded(path, file.name);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            "Couldn't upload that video — check your connection and try again.",
      );
    } finally {
      if (mounted) {
        setState(() {
          _progress = null;
          _uploadingName = null;
        });
      }
    }
  }

  static String _mb(int bytes) =>
      "${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB";

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final path = widget.videoPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (progress != null) ...[
          Text(
            _uploadingName ?? "Uploading…",
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.line,
              valueColor: AlwaysStoppedAnimation(AppColors.gold),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            // The bar stops just short of full until the server confirms, so
            // the wording has to carry that last step rather than sit at 99%.
            progress >= 0.99
                ? "Finishing up…"
                : "Uploading — ${(progress * 100).toStringAsFixed(0)}%",
            style: TextStyle(fontSize: 11, color: AppColors.mute),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Keep this screen open until it finishes.",
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mute,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ] else if (path != null) ...[
          // Paused on its first frame: this is here to show the coach what
          // the exercise has, not to play at them while they edit it.
          ExerciseVideoPlayer(
            key: ValueKey(path),
            videoPath: path,
            autoPlay: false,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.videoName ?? "Demo video",
                  style: TextStyle(fontSize: 12, color: AppColors.mute),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              BtnGhost(onPressed: _pick, child: const Text("Replace")),
              const SizedBox(width: 6),
              TextButton(
                onPressed: widget.onRemoved,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.errorText,
                ),
                child: const Text("Remove"),
              ),
            ],
          ),
        ] else
          Row(
            children: [
              BtnGhost(
                onPressed: _pick,
                child: const Text("+ Upload video"),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "MP4 or MOV, up to ${_mb(SupabaseService.kExerciseVideoMaxBytes)}.",
                  style: TextStyle(fontSize: 11, color: AppColors.mute),
                ),
              ),
            ],
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: TextStyle(fontSize: 11, color: AppColors.errorText),
            ),
          ),
        if (progress == null && path == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "The video is saved with the exercise, so remember to press Save.",
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mute,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChipPicker extends StatelessWidget {
  const _ChipPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final selected = value == o;
        return InkWell(
          onTap: () => onChanged(o),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold
                  : AppColors.card,
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.line,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              o,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.onGold : AppColors.txt,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
