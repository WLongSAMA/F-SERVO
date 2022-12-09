
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../stateManagement/ChangeNotifierWidget.dart';
import '../../../stateManagement/openFileTypes.dart';
import '../../../stateManagement/openFilesManager.dart';
import '../../../utils/utils.dart';
import '../../misc/ColumnSeparated.dart';
import '../../theme/customTheme.dart';
import 'AudioFileEditor.dart';

class WemFileEditor extends ChangeNotifierWidget {
  final WemFileData wem;
  final bool lockControls;
  final bool topPadding;
  final bool showOverride;

  WemFileEditor({ super.key, required this.wem, this.lockControls = false, this.topPadding = false, this.showOverride = true })
    : super(notifier: wem);

  @override
  State<WemFileEditor> createState() => _WemFileEditorState();
}

class _WemFileEditorState extends ChangeNotifierState<WemFileEditor> {
  Key refreshKey = UniqueKey();

  @override
  void initState() {
    widget.wem.overrideData.addListener(_onOverrideChanged);
    widget.wem.onOverrideApplied.addListener(_onOverrideApplied);
    super.initState();
  }

  @override
  void dispose() {
    widget.wem.overrideData.removeListener(_onOverrideChanged);
    widget.wem.onOverrideApplied.removeListener(_onOverrideApplied);
    super.dispose();
  }

  void _onOverrideChanged() => setState(() {});

  void _onOverrideApplied() => setState(() => refreshKey = UniqueKey());

  Future<void> _pickOverride() async {
    var files = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
      allowedExtensions: ["wav"],
    );
    if (files == null)
      return;
    var file = files.files.first;
    if (!file.path!.endsWith(".wav")) {
      showToast("Please select a .wav file");
      return;
    }
    var wavFile = WavFileData(file.path!);
    await wavFile.load();
    widget.wem.overrideData.value = wavFile;
  }

  @override
  Widget build(BuildContext context) {
    var audioEditor = Column(
      children: [
        AudioFileEditor(
          key: refreshKey,
          file: widget.wem,
          lockControls: widget.lockControls,
          additionalControls: widget.showOverride ? Wrap(
            children: [
              ElevatedButton(
                onPressed: _pickOverride,
                style: getTheme(context).dialogPrimaryButtonStyle,
                child: const Text("Select WAV"),
              ),
              const SizedBox(width: 10),
              if (widget.wem.overrideData.value != null)
                ElevatedButton(
                  onPressed: () => widget.wem.overrideData.value = null,
                  style: getTheme(context).dialogSecondaryButtonStyle,
                  child: const Text("Remove"),
                ),
            ],
          ) : null,
          rightSide: widget.wem.relatedBnkPlaylistIds.isNotEmpty ? Align(
            alignment: Alignment.centerRight,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: getTheme(context).propBorderColor!))
              ),
              padding: const EdgeInsets.only(left: 30),
              child: ColumnSeparated(
                children: [
                  Text(
                    "Used in ${pluralStr(widget.wem.relatedBnkPlaylistIds.length, "BNK playlist")}:    ",
                    style: const TextStyle(fontFamily: "FiraCode")
                  ),
                  for (var playlistId in widget.wem.relatedBnkPlaylistIds)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        style: getTheme(context).dialogSecondaryButtonStyle!.copyWith(
                          backgroundColor: MaterialStateProperty.all(getTheme(context).actionBgColor),
                        ),
                        onPressed: () => areasManager.openFile("${widget.wem.bgmBnkPath!}#p=$playlistId"),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.arrow_forward, size: 20),
                              const SizedBox(width: 10),
                              Text(playlistId.toString(), style: const TextStyle(fontFamily: "FiraCode")),
                            ],
                          ),
                        ),
                      ),
                    )
                ],
              ),
            ),
          ) : null,
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.wem.isReplacing ? 1 : 0,
          child: const SizedBox(
            height: 2,
            child: LinearProgressIndicator(backgroundColor: Colors.transparent),
          ),
        ),
        if (widget.showOverride && widget.wem.overrideData.value != null) ...[
          AudioFileEditor(
            key: Key(widget.wem.overrideData.value!.uuid),
            file: widget.wem.overrideData.value!,
            lockControls: widget.lockControls,
            additionalControls: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () => widget.wem.applyOverride(),
                  style: getTheme(context).dialogPrimaryButtonStyle,
                  child: const Text("Replace WEM"),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    if (widget.topPadding) {
      return Padding(
        padding: const EdgeInsets.only(top: 50),
        child: audioEditor,
      );
    }
    return audioEditor;
  }
}
