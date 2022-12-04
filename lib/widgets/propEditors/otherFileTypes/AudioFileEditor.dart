
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../stateManagement/ChangeNotifierWidget.dart';
import '../../../stateManagement/Property.dart';
import '../../../stateManagement/nestedNotifier.dart';
import '../../../stateManagement/openFileTypes.dart';
import '../../../utils/utils.dart';
import '../../misc/FlexReorderable.dart';
import '../../misc/mousePosition.dart';
import '../../theme/customTheme.dart';
import '../simpleProps/AudioSampleNumberPropTextField.dart';
import '../simpleProps/UnderlinePropTextField.dart';
import '../simpleProps/propEditorFactory.dart';
import '../simpleProps/propTextField.dart';

class AudioFileEditor extends StatefulWidget {
  final AudioFileData file;
  final bool lockControls;
  final Widget? additionalControls;

  const AudioFileEditor({ super.key, required this.file, this.lockControls = false, this.additionalControls });

  @override
  State<AudioFileEditor> createState() => _AudioFileEditorState();
}

class _AudioFileEditorState extends State<AudioFileEditor> {
  late final AudioPlayer? _player;
  final ValueNotifier<int> _viewStart = ValueNotifier(0);
  final ValueNotifier<int> _viewEnd = ValueNotifier(1000);

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    widget.file.load().then((_) {
      if (!mounted)
        return;
      _player!.setSourceDeviceFile(widget.file.audioFilePath!);
      _viewEnd.value = widget.file.totalSamples;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _player!.dispose();
    _viewStart.dispose();
    _viewEnd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.file.audioFilePath == null)
            const SizedBox(
              height: 2,
              child: LinearProgressIndicator(backgroundColor: Colors.transparent,)
            ),
          _TimelineEditor(
            file: widget.file,
            player: _player,
            lockControls: widget.lockControls,
            viewStart: _viewStart,
            viewEnd: _viewEnd,
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Center(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "  ${widget.file.name}",
                        style: const TextStyle(fontFamily: "FiraCode", fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.first_page),
                            onPressed: () => _player?.seek(Duration.zero),
                          ),
                          StreamBuilder(
                            stream: _player?.onPlayerStateChanged,
                            builder: (context, snapshot) => IconButton(
                              icon: _player?.state == PlayerState.playing
                                ? const Icon(Icons.pause)
                                : const Icon(Icons.play_arrow),
                              onPressed: _player?.state == PlayerState.playing
                                ? _player?.pause
                                : _player?.resume,
                            )
                          ),
                          IconButton(
                            icon: const Icon(Icons.last_page),
                            onPressed: () => _player?.seek(Duration(milliseconds: widget.file.totalSamples ~/ widget.file.samplesPerSec - 200)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.repeat),
                            color: _player?.releaseMode == ReleaseMode.loop ? Theme.of(context).colorScheme.secondary : null,
                            onPressed: () => _player?.setReleaseMode(_player?.releaseMode == ReleaseMode.loop ? ReleaseMode.stop : ReleaseMode.loop)
                                                    .then((_) => setState(() {})),
                          ),
                          const SizedBox(width: 15),
                          DurationStream(
                            time: _player?.onPositionChanged,
                          ),
                          Text(" / ${widget.file.duration != null ? formatDuration(widget.file.duration!) : "00:00"}"),
                          const SizedBox(width: 15),
                        ],
                      ),
                      if (widget.additionalControls != null) ...[
                        const SizedBox(height: 10),
                        widget.additionalControls!,
                      ]
                    ],
                  ),
                ),
              ),
              _CuePointsEditor(
                cuePoints: widget.file.cuePoints,
                file: widget.file,
              ),  
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelineEditor extends ChangeNotifierWidget {
  final AudioFileData file;
  final AudioPlayer? player;
  final bool lockControls;
  final ValueNotifier<int> viewStart;
  final ValueNotifier<int> viewEnd;

  _TimelineEditor({ required this.file, required this.player,
    required this.lockControls, required this.viewStart, required this.viewEnd })
    : super(notifier: file.cuePoints);

  @override
  State<_TimelineEditor> createState() => __TimelineEditorState();
}

class __TimelineEditorState extends ChangeNotifierState<_TimelineEditor> {
  int _currentPosition = 0;
  late StreamSubscription<Duration> updateSub;
  ValueNotifier<int> get viewStart => widget.viewStart;
  ValueNotifier<int> get viewEnd => widget.viewEnd;

  @override
  void initState() {
    updateSub = widget.player!.onPositionChanged.listen(_onPositionChange);
    super.initState();
  }

  @override
  void dispose() {
    updateSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 100,
          child: Listener(
            onPointerSignal: !widget.lockControls ? _onPointerSignal : null,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _onTimelineTap,
                    onHorizontalDragUpdate: !widget.lockControls ? _onHorizontalDragUpdate : null,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        samples: widget.file.wavSamples,
                        viewStart: viewStart.value,
                        viewEnd: viewEnd.value,
                        totalSamples: widget.file.totalSamples,
                        curSample: _currentPosition,
                        samplesPerSec: widget.file.samplesPerSec,
                        scaleFactor: MediaQuery.of(context).devicePixelRatio,
                        lineColor: Theme.of(context).colorScheme.primary,
                        textColor: getTheme(context).textColor!.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
                for (var cuePoint in widget.file.cuePoints)
                  ChangeNotifierBuilder(
                    key: Key(cuePoint.uuid),
                    notifiers: [cuePoint.sample, cuePoint.name],
                    builder: (context) => Positioned(
                      left: (cuePoint.sample.value - viewStart.value) / (viewEnd.value - viewStart.value) * constraints.maxWidth - 8,
                      top: 0,
                      bottom: 0,
                      child: _CuePointMarker(
                        cuePoint: cuePoint,
                        viewStart: viewStart,
                        viewEnd: viewEnd,
                        totalSamples: widget.file.totalSamples,
                        samplesPerSec: widget.file.samplesPerSec,
                        parentWidth: constraints.maxWidth,
                        onDrag: _onCuePointDrag,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    );
  }

  void _onPositionChange(event) {
    if (!mounted)
      return;
    setState(() => _currentPosition = event.inMicroseconds * widget.file.samplesPerSec ~/ 1000000);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent)
      return;
    double delta = event.scrollDelta.dy;
    int viewArea = viewEnd.value - viewStart.value;
    // zoom in/out by 10% of the view area
    if (delta < 0) {
      viewStart.value = max((viewStart.value + viewArea * 0.1).round(), 0);
      viewEnd.value = min((viewEnd.value - viewArea * 0.1).round(), widget.file.totalSamples);
    } else {
      viewStart.value = max((viewStart.value - viewArea * 0.1).round(), 0);
      viewEnd.value= min((viewEnd.value + viewArea * 0.1).round(), widget.file.totalSamples);
    }
    setState(() {});
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    var totalViewWidth = context.size!.width;
    int viewArea = viewEnd.value - viewStart.value;
    int delta = (details.delta.dx / totalViewWidth * viewArea).round();
    if (delta > 0) {
      int maxChange = viewStart.value;
      delta = min(delta, maxChange);
    } else {
      int maxChange = widget.file.totalSamples - viewEnd.value;
      delta = max(delta, -maxChange);
    }
    viewStart.value -= delta;
    viewEnd.value -= delta;
    setState(() {});
  }

  void _onTimelineTap() {
    var renderBox = context.findRenderObject() as RenderBox;
    var locTapPos = renderBox.globalToLocal(MousePosition.pos);
    var xPos = locTapPos.dx;
    double relX = xPos / context.size!.width;
    int viewArea = viewEnd.value - viewStart.value;
    int newPosition = (viewStart.value + relX * viewArea).round();
    _currentPosition = clamp(newPosition, 0, widget.file.totalSamples);
    widget.player!.seek(Duration(microseconds: _currentPosition * 1000000 ~/ widget.file.samplesPerSec));
  }

  void _onCuePointDrag(double xPos, CuePointMarker cuePoint) {
    var renderBox = context.findRenderObject() as RenderBox;
    var localPos = renderBox.globalToLocal(Offset(xPos, 0));
    int viewArea = viewEnd.value - viewStart.value;
    int sample = (localPos.dx / context.size!.width * viewArea + viewStart.value).round();
    sample = clamp(sample, 0, widget.file.totalSamples - 1);
    cuePoint.sample.value = sample;
    setState(() {});
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double>? samples;
  final int viewStart;
  final int viewEnd;
  final int totalSamples;
  final int curSample;
  final int samplesPerSec;
  final double scaleFactor;
  final Color lineColor;
  final Color textColor;
  Size prevSize = Size.zero;

  static const Map<int, double> viewWidthMsToMarkerInterval = {
    50: 0.0025,
    100: 0.005,
    250: 0.025,
    500: 0.05,
    1000: 0.125,
    2000: 0.25,
    5000: 0.5,
    10000: 1,
    20000: 2.5,
    50000: 5,
    100000: 10,
    200000: 20,
    500000: 30,
    1000000: 60,
  };

  _WaveformPainter({
    required this.samples,
    required this.viewStart, required this.viewEnd,
    required this.totalSamples, required this.curSample, required this.samplesPerSec,
     required this.scaleFactor, required this.lineColor, required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    prevSize = size;
    if (samples != null)
      paintWaveform(canvas, size, samples!);
    else
      paintTimeline(canvas, size);
    paintTimeMarkers(canvas, size);
  }
  
  void paintWaveform(Canvas canvas, Size size, List<double> samples) {
    // only show samples that are in the view up to pixel resolution
    double viewStartRel = viewStart / totalSamples;
    double viewEndRel = viewEnd / totalSamples;
    double curSampleRel = curSample / totalSamples;
    int startSample = (viewStartRel * samples.length).round();
    int endSample = (viewEndRel * samples.length).round();
    int curSampleIdx = (curSampleRel * samples.length).round();
    curSampleIdx = clamp(curSampleIdx, startSample, endSample);
    double curSampleX = (curSampleIdx - startSample) / (endSample - startSample) * size.width;
    List<double> viewSamples = samples.sublist(startSample, endSample);
    List<double> playedSamples = samples.sublist(startSample, curSampleIdx);
    List<double> unplayedSamples = samples.sublist(curSampleIdx, endSample);

    // the denser the view, the lower the opacity
    double samplesPerPixel = viewSamples.length / size.width;
    double opacity;
    if (scaleFactor == 1)
      opacity = (-samplesPerPixel/40+1).clamp(0.1, 1).toDouble();
    else
      opacity = 1;
    Color color = lineColor.withOpacity(opacity);
    int bwColorVal = (color.red + color.green + color.blue) ~/ 3;
    Color bwColor = Color.fromARGB(color.alpha, bwColorVal, bwColorVal, bwColorVal);
    _paintSamples(canvas, size, playedSamples, color, 0, curSampleX);
    _paintSamples(canvas, size, unplayedSamples, bwColor, curSampleX, size.width);
  }

  double _paintSamples(Canvas canvas, Size size, List<double> samples, Color color, double startX, double endX) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    var height = size.height - 20;
    var path = Path();
    var x = startX;
    var y = height / 2;
    var xStep = (endX - startX) / samples.length;
    var yStep = height;
    path.moveTo(x, y);
    for (var i = 0; i < samples.length; i++) {
      x += xStep;
      y = height / 2 - samples[i] * yStep;
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);

    return x;
  }

  void paintTimeline(Canvas canvas, Size size) {
    double curSampleRel = (curSample - viewStart) / (viewEnd - viewStart);
    double curSampleX = curSampleRel * size.width;
    double playedWidth = curSampleX;

    int bwColorVal = (lineColor.red + lineColor.green + lineColor.blue) ~/ 3;
    Color bwColor = Color.fromARGB(lineColor.alpha, bwColorVal, bwColorVal, bwColorVal);
    _paintTimeline(canvas, size, playedWidth, size.width, bwColor);
    _paintTimeline(canvas, size, 0, playedWidth, lineColor);
  }

  void _paintTimeline(Canvas canvas, Size size, double startX, double endX, Color color) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    var path = Path();
    var startOffset = startX == 0 ? 10 : 0;
    var endOffset = endX == size.width ? -10 : 0;
    path.moveTo(clamp(startX + startOffset, 10, size.width), size.height / 2);
    path.lineTo(clamp(endX + endOffset, 10, size.width), size.height / 2);
    canvas.drawPath(path, paint);
  }

  void paintTimeMarkers(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = textColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    var textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    double viewAreaSec = (viewEnd - viewStart) / samplesPerSec;
    double markersIntervalSec = 1;
    for (var entry in viewWidthMsToMarkerInterval.entries) {
      if (viewAreaSec * 1000 < entry.key) {
        markersIntervalSec = entry.value;
        break;
      }
    }
    int markersIntervalSamples = (markersIntervalSec * samplesPerSec).round();
    int markersStart = (viewStart / markersIntervalSamples).ceil() * markersIntervalSamples;
    int markersEnd = (viewEnd / markersIntervalSamples).floor() * markersIntervalSamples;

    const double fontSize = 12;
    for (int i = markersStart; i <= markersEnd; i += markersIntervalSamples) {
      double x = (i - viewStart) / (viewEnd - viewStart) * size.width;
      if (x.isNaN || x.isInfinite)
        continue;
      // small marker on the bottom
      double yOff = size.height - fontSize;
      canvas.drawLine(Offset(x, yOff - 5), Offset(x, size.height), paint);
      // text to the right
      double totalSecs = i / samplesPerSec;
      String text = formatDuration(Duration(milliseconds: (totalSecs * 1000).round()), true);
      textPainter.text = TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 4, yOff - 3));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is _WaveformPainter)
      return oldDelegate.viewStart != viewStart
        || oldDelegate.viewEnd != viewEnd
        || oldDelegate.prevSize != prevSize;
    return true;
  }
}

// class _CurrentPositionMarker extends StatefulWidget {
//   final void Function(double delta) onDrag;
//   final Stream<Duration> positionChangeStream;
//
//   const _CurrentPositionMarker({ super.key, required this.onDrag, required this.positionChangeStream });
//
//   @override
//   State<_CurrentPositionMarker> createState() => _CurrentPositionMarkerState();
// }
//
// class _CurrentPositionMarkerState extends State<_CurrentPositionMarker> {
//   late final StreamSubscription<Duration> _positionChangeSubscription;
//
//   @override
//   void initState() {
//     super.initState();
//     _positionChangeSubscription = widget.positionChangeStream.listen((position) {
//       print("position changed: $position");
//       setState(() {});
//     });
//   }
//
//   @override
//   void dispose() {
//     _positionChangeSubscription.cancel();
//     MousePosition.removeDragListener(_onDrag);
//     MousePosition.removeDragEndListener(_onDragEnd);
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return DebugContainer(
//       child: GestureDetector(
//         onPanStart: (_) {
//           MousePosition.addDragListener(_onDrag);
//           MousePosition.addDragEndListener(_onDragEnd);
//         },
//         behavior: HitTestBehavior.translucent,
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 12),
//           child: Container(
//             width: 2,
//             color: Theme.of(context).colorScheme.secondary,
//           ),
//         ),
//       ),
//     );
//   }
//
//   void _onDrag(Offset pos) {
//     print("drag $pos");
//     var renderBox = context.findRenderObject() as RenderBox;
//     var localPos = renderBox.globalToLocal(pos);
//     widget.onDrag(localPos.dx);
//   }
//
//   void _onDragEnd() {
//     MousePosition.removeDragListener(_onDrag);
//     MousePosition.removeDragEndListener(_onDragEnd);
//   }
// }

class _CuePointMarker extends ChangeNotifierWidget {
  final CuePointMarker cuePoint;
  final ValueNotifier<int> viewStart;
  final ValueNotifier<int> viewEnd;
  final int totalSamples;
  final int samplesPerSec;
  final double parentWidth;
  final void Function(double xPos, CuePointMarker cuePoint) onDrag;

  _CuePointMarker({
    required this.cuePoint,
    required this.viewStart, required this.viewEnd,
    required this.totalSamples, required this.samplesPerSec,
    required this.parentWidth, required this.onDrag,
  }) : super(notifiers: [viewStart, viewEnd, cuePoint.sample]);

  @override
  State<_CuePointMarker> createState() => __CuePointMarkerState();
}

class __CuePointMarkerState extends ChangeNotifierState<_CuePointMarker> {
  OverlayEntry? _textOverlay;

  @override
  void dispose() {
    MousePosition.removeDragListener(_onDrag);
    MousePosition.removeDragEndListener(_onDragEnd);
    _textOverlay?.remove();
    super.dispose();
  }

  void onMouseEnter(_) {
    var renderBox = context.findRenderObject() as RenderBox;
    var pos = renderBox.localToGlobal(Offset.zero); 
    var size = renderBox.size;
    var isOnLeftSide = MousePosition.pos.dx < MediaQuery.of(context).size.width / 2;

    _textOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: isOnLeftSide ? pos.dx + size.width / 2 : null,
        right: isOnLeftSide ? null : MediaQuery.of(context).size.width - pos.dx,
        top: pos.dy - 15,
        child: Material(
          color: Colors.transparent,
          child: Text(
            widget.cuePoint.name.value,
            style: TextStyle(
              color: getTheme(context).textColor!.withOpacity(0.8),
              fontSize: 12,
              fontFamily: "FiraCode",
            ),
          )
        ),
      ),
    );
    Overlay.of(context)!.insert(_textOverlay!);
  }

  void onMouseLeave(_) {
    _textOverlay?.remove();
    _textOverlay = null;    
  }

  @override
  Widget build(BuildContext context) {
    if (!between(widget.cuePoint.sample.value, widget.viewStart.value, widget.viewEnd.value))
      return const SizedBox.shrink();
    
    const double leftPadding = 8;
    return MouseRegion(
      onEnter: onMouseEnter,
      onExit: onMouseLeave,
      child: Stack(
        children: [
          Positioned(
            left: -17,
            top: -21.5,
            child: Icon(
              Icons.arrow_drop_down_rounded,
              color: Theme.of(context).colorScheme.secondary,
              size: 50,
            ),
          ),
          // line
          Positioned(
            child: GestureDetector(
              onPanStart: (_) {
                MousePosition.addDragListener(_onDrag);
                MousePosition.addDragEndListener(_onDragEnd);
              },
              behavior: HitTestBehavior.translucent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: leftPadding),
                child: Container(
                  width: 2,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onDrag(Offset pos) {
    widget.onDrag(pos.dx, widget.cuePoint);
  }

  void _onDragEnd() {
    MousePosition.removeDragListener(_onDrag);
    MousePosition.removeDragEndListener(_onDragEnd);
  }
}

class DurationStream extends StreamBuilder<Duration> {
  DurationStream({ super.key, required Stream<Duration>? time }) : super(
    stream: time,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        var pos = snapshot.data!;
        return Text(formatDuration(pos));
      } else {
        return const Text("00:00");
      }
    }
  );
}

class _CuePointsEditor extends ChangeNotifierWidget {
  final NestedNotifier<CuePointMarker> cuePoints;
  final AudioFileData file;

  _CuePointsEditor({ required this.cuePoints, required this.file }) : super(notifier: cuePoints);

  @override
  State<_CuePointsEditor> createState() => __CuePointsEditorState();
}

class __CuePointsEditorState extends ChangeNotifierState<_CuePointsEditor> {
  @override
  Widget build(BuildContext context) {
    return ColumnReorderable(
      crossAxisAlignment: CrossAxisAlignment.start,
      onReorder: widget.cuePoints.move,
      header: Row(
        children: [
          const SizedBox(
            width: 170,
            child: Text("Time", textAlign: TextAlign.center, textScaleFactor: 0.9, style: TextStyle(fontFamily: "FiraCode"),),
          ),
          const SizedBox(width: 8),
          const SizedBox(
            width: 150,
            child: Text("Cue Point Name", textAlign: TextAlign.center, textScaleFactor: 0.9, style: TextStyle(fontFamily: "FiraCode"),),
          ),
          IconButton(
            onPressed: _copyToClipboard,
            iconSize: 14,
            splashRadius: 18,
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            onPressed: _pasteFromClipboard,
            iconSize: 14,
            splashRadius: 18,
            icon: const Icon(Icons.paste),
          ),
        ],
      ),
      footer: Row(
        children: [
          const SizedBox(width: 170 + 8 + 150 + 27),
          IconButton(
            onPressed: () {
              widget.cuePoints.add(CuePointMarker(
                AudioSampleNumberProp(0, widget.file.samplesPerSec),
                StringProp("Marker ${widget.cuePoints.length + 1}"),
                widget.file.uuid
              ));
            },
            iconSize: 20,
            splashRadius: 18,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      children: widget.cuePoints.map((p) => ChangeNotifierBuilder(
        key: Key(p.uuid),
        notifier: p.sample,
        builder: (context) {
          return Row(
            children: [
              IconButton(
                onPressed: () => p.sample.value = 0,
                color: p.sample.value == 0 ? Theme.of(context).colorScheme.secondary.withOpacity(0.75) : null,
                splashRadius: 18,
                icon: const Icon(Icons.arrow_left),
              ),
              AudioSampleNumberPropTextField<UnderlinePropTextField>(
                prop: p.sample,
                samplesCount: widget.file.totalSamples,
                samplesPerSecond: widget.file.samplesPerSec,
                options: const PropTFOptions(
                  hintText: "sample",
                  constraints: BoxConstraints.tightFor(width: 90),
                  useIntrinsicWidth: false,
                ),
              ),
              IconButton(
                onPressed: () => p.sample.value = widget.file.totalSamples - 1,
                color: p.sample.value == widget.file.totalSamples ? Theme.of(context).colorScheme.secondary.withOpacity(0.75) : null,
                splashRadius: 18,
                icon: const Icon(Icons.arrow_right),
              ),
              const SizedBox(width: 8),
              makePropEditor<UnderlinePropTextField>(p.name, const PropTFOptions(
                hintText: "name",
                constraints: BoxConstraints(minWidth: 150),
              )),
              IconButton(
                onPressed: () => widget.cuePoints.remove(p),
                iconSize: 16,
                splashRadius: 18,
                icon: const Icon(Icons.close),
              ),
              const FlexDraggableHandle(
                child: Icon(Icons.drag_handle, size: 16),
              )
            ],
          );
        }
      )).toList(),
    );
  }

  void _copyToClipboard() {
    var cuePointsList = widget.cuePoints.map((e) => {
      "sample": e.sample.value,
      "name": e.name.value,
    }).toList();
    var data = {
      "samplesPerSec": widget.file.samplesPerSec,
      "cuePoints": cuePointsList,
    };
    copyToClipboard(const JsonEncoder.withIndent("\t").convert(data));
    showToast("Copied ${cuePointsList.length} cue points to clipboard");
  }

  void _pasteFromClipboard() async {
    var data = await getClipboardText();
    if (data == null)
      return;
    try {
      var json = jsonDecode(data);
      var sampleRate = json["samplesPerSec"];
      if (sampleRate is! int)
        throw Exception("Invalid sample rate $sampleRate");
      var sampleScale = widget.file.samplesPerSec / sampleRate;
      var cuePoints = (json["cuePoints"] as List).map((e) {
        var sample = e["sample"];
        var name = e["name"];
        if (sample is! int || name is! String)
          throw Exception("Invalid cue point $e");
        sample = (sample * sampleScale).round();
        sample = clamp(sample, 0, widget.file.totalSamples);
        return CuePointMarker(
          AudioSampleNumberProp(sample, widget.file.samplesPerSec),
          StringProp(name),
          widget.file.uuid
        );
      }).whereType<CuePointMarker>().toList();
      widget.cuePoints.addAll(cuePoints);
    } catch (e) {
      showToast("Invalid Clipboard Data");
      rethrow;
    }
  }
}
