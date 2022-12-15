import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/cupertino.dart';
import 'package:pip_flutter/utils/pip_video_record.dart';

enum TimerState { idle, start, pause, mark }

typedef TimerCallback = void Function(Map<String, dynamic>);

class PipTimer {
  TimerState _eventName = TimerState.idle;
  DateTime _eventTime = DateTime.now();
  int _eventProgress = 0;
  final TimerCallback callback;
  final int markInterval;
  final SendPort? sendPort;

  PipTimer({required this.callback, this.markInterval = 30, this.sendPort}){
    _controller.stream..listen((event) {
      print("接收回调事件:::: onEventChanged timer start");
      callback.call(event);
      try {
        sendPort?.send(PipVideoRecord.fromJson(event));
      } catch (e) {
        print("eee===>$e  ${StackTrace.current}");
      }
    });
  }

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>();


  Timer? _countingTimer;

  int _timeInterval=0;
  int _markTempTimeInterval=0;
  
  // 开始计时
  void start({int? progress=null}) {
    print("timer start");
    if (_eventName != TimerState.idle && _eventName != TimerState.pause) {
      print("接收回调事件::::  timer start");
      return;
    }
    _eventName = TimerState.start;
    _eventTime = DateTime.now();

    _timeInterval=0;
    _markTempTimeInterval=0;
    _countingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      // Do something here
      _timeInterval++;
    });
    print("接收回调事件:::: onEventChanged timer add");

    if(progress!=null){
      _eventProgress = progress!;
    }
    _controller.add({
      'event_name': _eventName.name,
      'event_interval': 0,
      'event_time': _eventTime.toString().substring(0, 19),
      'event_progress': _eventProgress
    });
  }


  // 暂停计时
  void pause() {
    print("timer pause");
    if (_eventName == TimerState.pause || _eventName == TimerState.idle) return;
    _eventName = TimerState.pause;
    _eventTime = DateTime.now();
    final oldInterval = _markTempTimeInterval;
    _markTempTimeInterval = _timeInterval;
    final newInterval = _markTempTimeInterval;
    final eventInterval = newInterval - oldInterval;

    _countingTimer?.cancel();
    _countingTimer = null;
    _timeInterval=0;
    _markTempTimeInterval=0;
    _controller.add({
      'event_name': _eventName.name,
      'event_interval': eventInterval,
      'event_time': _eventTime.toString().substring(0, 19),
      'event_progress': _eventProgress
    });

  }

  // 打点  // 进度
  void mark(int currentProgress,{bool force=false}) {
    print("markmarkmarkmark====>>${force}  ${StackTrace.current}");
    _eventProgress = currentProgress;
    if (_eventName == TimerState.idle || _eventName == TimerState.pause) return;
    if(!force){
      if (DateTime.now().difference(_eventTime).inSeconds < markInterval) return;
    }
    _eventName = TimerState.mark;
    _eventTime = DateTime.now();
    final oldInterval = _markTempTimeInterval;
    _markTempTimeInterval = _timeInterval;
    final newInterval = _markTempTimeInterval;
    final eventInterval = newInterval - oldInterval;
    _controller.add({
      'event_name': _eventName.name,
      'event_interval': eventInterval,
      'event_time': _eventTime.toString().substring(0, 19),
      'event_progress': _eventProgress
    });
  }

}

class PortContainer {
  SendPort port;

  PortContainer(this.port);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  String video_id = "q12131313123";
  String user_id = "1008611";
  String? video_record_id = "10010";

  Future.delayed(const Duration(milliseconds: 100)).then((value) async {
    final db = PipVideoRecordDatabase();
    await db.init();
    final receivePort = ReceivePort();
    final timer = PipTimer(
        callback: (e) {
          e.addAll({
            'video_id': video_id,
            'user_id': user_id,
            'video_record_id': video_record_id,
          });
          print("timer:$e");
        },
        markInterval: 4,
        sendPort: receivePort.sendPort);
    await Isolate.spawn(testIsolate, PortContainer(receivePort.sendPort));
    receivePort.listen((data) {
      print("receivePort.listen((data)${data}");
      if (data is PortContainer) {
        final sendPort = data.port;
        sendPort.send(timer);
      } else if (data is PipVideoRecord) {
        db.addRecord(data);
      } else {
        db.getUserRecords(user_id).then((events) {
          print("events===>>${events.map((e) => jsonEncode(e.toJson()))}");
        });
      }
    });
  });
}

Future<void> testIsolate(PortContainer portContainer) async {
  final port = portContainer.port;
  final receivePort = ReceivePort();

  port.send(PortContainer(receivePort.sendPort));
  final pipTimer = await receivePort.first as PipTimer;

  int progress = 0;
  Future.delayed(const Duration(seconds: 4)).then((value) {
    pipTimer.start();
    Timer.periodic(const Duration(milliseconds: 600), (timer) {
      progress++;
      pipTimer.mark(progress);
    });
    Future.delayed(const Duration(seconds: 30)).then((value) {
      pipTimer.pause();
      Future.delayed(const Duration(milliseconds: 300)).then((value) {
        Isolate.exit();
      });
    });
  });
}
