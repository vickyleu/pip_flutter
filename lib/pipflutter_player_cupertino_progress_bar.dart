import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:pip_flutter/pipflutter_player_controller.dart';
import 'package:pip_flutter/pipflutter_player_progress_colors.dart';
import 'package:pip_flutter/video_player.dart';
import 'package:pip_flutter/video_player_platform_interface.dart';

class PipFlutterPlayerCupertinoVideoProgressBar extends StatefulWidget {
  PipFlutterPlayerCupertinoVideoProgressBar(
    this.controller,
    this.pipFlutterPlayerController, {
    PipFlutterPlayerProgressColors? colors,
    this.onDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onTapDown,
    Key? key,
  })  : colors = colors ?? PipFlutterPlayerProgressColors(),
        super(key: key);

  final VideoPlayerController? controller;
  final PipFlutterPlayerController? pipFlutterPlayerController;
  final PipFlutterPlayerProgressColors colors;
  final Function()? onDragStart;
  final Function()? onDragEnd;
  final Function()? onDragUpdate;
  final Function()? onTapDown;

  @override
  _VideoProgressBarState createState() {
    return _VideoProgressBarState();
  }
}

class _VideoProgressBarState
    extends State<PipFlutterPlayerCupertinoVideoProgressBar> {
  _VideoProgressBarState() {
    listener = () {
      setState(() {});
    };
  }

  late VoidCallback listener;
  bool _controllerWasPlaying = false;

  VideoPlayerController? get controller => widget.controller;

  PipFlutterPlayerController? get pipFlutterPlayerController =>
      widget.pipFlutterPlayerController;

  bool shouldPlayAfterDragEnd = false;
  Duration? lastSeek;
  Timer? _updateBlockTimer;

  @override
  void initState() {
    super.initState();
    controller!.addListener(listener);
  }

  @override
  void deactivate() {
    controller!.removeListener(listener);
    _cancelUpdateBlockTimer();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag = pipFlutterPlayerController!
        .pipFlutterPlayerConfiguration
        .controlsConfiguration
        .enableProgressBarDrag;
    return GestureDetector(
      onHorizontalDragStart: (DragStartDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }
        _controllerWasPlaying = controller!.value.isPlaying;
        if (_controllerWasPlaying) {
          controller!.pause();
        }

        if (widget.onDragStart != null) {
          widget.onDragStart!();
        }
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }
        seekToRelativePosition(details.globalPosition);

        if (widget.onDragUpdate != null) {
          widget.onDragUpdate!();
        }
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (!enableProgressBarDrag) {
          return;
        }
        if (_controllerWasPlaying) {
          pipFlutterPlayerController?.play();
          shouldPlayAfterDragEnd = true;
        }
        _setupUpdateBlockTimer();

        if (widget.onDragEnd != null) {
          widget.onDragEnd!();
        }
      },
      onTapDown: (TapDownDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }

        seekToRelativePosition(details.globalPosition);
        _setupUpdateBlockTimer();
        if (widget.onTapDown != null) {
          widget.onTapDown!();
        }
      },
      child: Center(
        child: Container(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          color: Colors.transparent,
          child: CustomPaint(
            painter: _ProgressBarPainter(
              _getValue(),
              widget.colors,
            ),
          ),
        ),
      ),
    );
  }

  void _setupUpdateBlockTimer() {
    _updateBlockTimer = Timer(const Duration(milliseconds: 1000), () {
      lastSeek = null;
      _cancelUpdateBlockTimer();
    });
  }

  void _cancelUpdateBlockTimer() {
    _updateBlockTimer?.cancel();
    _updateBlockTimer = null;
  }
  VideoPlayerValue _getValue() {
    if (lastSeek != null) {
      final value= controller!.value.copyWith(position: lastSeek);
      return value;
    } else {
      final value= controller!.value;
      return value;
    }
  }

  void seekToRelativePosition(Offset globalPosition) async {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject != null) {
      final box = renderObject as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = tapPos.dx / box.size.width;
      if (relative > 0) {
        final Duration position = controller!.value.duration! * relative;
        lastSeek = position;
        await pipFlutterPlayerController!.seekTo(position);
        onFinishedLastSeek();
        if (relative >= 1) {
          lastSeek = controller!.value.duration;
          await pipFlutterPlayerController!.seekTo(controller!.value.duration!);
          onFinishedLastSeek();
        }
      }
    }
  }

  void onFinishedLastSeek() {
    if (shouldPlayAfterDragEnd) {
      shouldPlayAfterDragEnd = false;
      pipFlutterPlayerController?.play();
    }
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter(this.value, this.colors);

  VideoPlayerValue value;
  PipFlutterPlayerProgressColors colors;

  @override
  bool shouldRepaint(CustomPainter painter) {
    return true;
  }


  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 5.0;
    const handleHeight = 6.0;
    final baseOffset = size.height / 2 - barHeight / 2.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, baseOffset),
          Offset(size.width, baseOffset + barHeight),
        ),
        const Radius.circular(4.0),
      ),
      colors.backgroundPaint,
    );
    if (!value.initialized) {
      return;
    }
    final double playedPartPercent =
        value.position.inMilliseconds / value.duration!.inMilliseconds;
    final double playedPart =
        playedPartPercent > 1 ? size.width : playedPartPercent * size.width;


    value.buffered.sort((a, b) => a.start.compareTo(b.start)); // 先按照开始时间排序

    List<DurationRange> bufferedRanges = [];
    bufferedRanges.addAll(value.buffered);
    // 合并和拆分范围
    List<DurationRange> finalRanges = [];
    if(bufferedRanges.isNotEmpty){
      // 定义一个方法用于合并两个范围
      DurationRange currentRange = bufferedRanges[0];
      for (int i = 1; i < bufferedRanges.length; i++) {
        DurationRange nextRange = bufferedRanges[i];
        if (currentRange.end.inSeconds >= nextRange.start.inSeconds) {
          // 范围重叠，合并
          currentRange = currentRange.merge(nextRange);
        } else {
          // 范围不重叠，保存当前范围并开始新的范围
          finalRanges.add(currentRange);
          currentRange = nextRange;
        }
      }
      finalRanges.add(currentRange);
    }

    // 更新缓存范围的方法
    void updateBufferedRanges(List<DurationRange> finalRanges) {
      // 如果 _buffered 为空，直接将 finalRanges 复制到 _buffered
      if (value.alreadyBuffered.isEmpty) {
        value.alreadyBuffered.addAll(finalRanges);
        return;
      }

      // 否则，将 finalRanges 与 _buffered 最后一个范围合并
      DurationRange lastMergedRange = value.alreadyBuffered.removeLast();
      DurationRange firstNewRange = finalRanges.first;

      if (lastMergedRange.end.inSeconds >= firstNewRange.start.inSeconds) {
        // 范围重叠，合并
        finalRanges[0] = lastMergedRange.merge(firstNewRange);
      } else {
        // 范围不重叠，直接添加到 _buffered
        value.alreadyBuffered.add(lastMergedRange);
      }
      // 将剩余的 finalRanges 添加到 _buffered
      value.alreadyBuffered.addAll(finalRanges);
    }
    updateBufferedRanges(finalRanges);
    print("alreadyBuffered.length=${value.alreadyBuffered.length}");

    for (int i = 0; i < value.alreadyBuffered.length; i++) {
      DurationRange range = value.alreadyBuffered[i];
      final double start = range.startFraction(value.duration!) * size.width;
      final double end = range.endFraction(value.duration!) * size.width;
      print("start: $start, end: $end, playedPart: $playedPart");
      print("查询缓存时间 i=$i range:${range.start.inSeconds}==${range.end.inSeconds}");
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(
            Offset(start, baseOffset),
            Offset(end, baseOffset + barHeight),
          ),
          const Radius.circular(4.0),
        ),
        colors.bufferedPaint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(
          Offset(0.0, baseOffset),
          Offset(playedPart, baseOffset + barHeight),
        ),
        const Radius.circular(4.0),
      ),
      colors.playedPaint,
    );

    final shadowPath = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(playedPart, baseOffset + barHeight / 2),
          radius: handleHeight));

    canvas.drawShadow(shadowPath, Colors.black, 0.2, false);
    canvas.drawCircle(
      Offset(playedPart, baseOffset + barHeight / 2),
      handleHeight,
      colors.handlePaint,
    );
  }
}

extension _D on DurationRange{
  DurationRange merge(DurationRange other) {
    return DurationRange(
      Duration(
        seconds: start.inSeconds < other.start.inSeconds
            ? start.inSeconds
            : other.start.inSeconds,
      ),
      Duration(
        seconds: end.inSeconds > other.end.inSeconds
            ? end.inSeconds
            : other.end.inSeconds,
      ),
    );
  }
}
