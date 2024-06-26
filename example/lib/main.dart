import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:pip_flutter/pipflutter_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  String video_id = "q12131313123";
  String user_id = "1008613";
  String? video_record_id = "10010";
  runApp(const MyApp());
  /*Future.delayed(const Duration(milliseconds: 100)).then((value) async {
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
          JsonEncoder encoder = const JsonEncoder.withIndent('  ');
          print("timer:${encoder.convert(e)}");
        },
        markInterval: 4,
        sendPort: receivePort.sendPort);
    await Isolate.spawn(testIsolate, PortContainer(receivePort.sendPort));
    receivePort.listen((data) {
      if (data is PortContainer) {
        final sendPort = data.port;
        sendPort.send(timer);
      } else if (data is PipVideoRecord) {
        db.addRecord(data);
      } else {
        print("结束查询");
        db.getUserRecords(user_id).then((events) {
          JsonEncoder encoder = const JsonEncoder.withIndent('  ');
          print("events===>>${events.map((e) => encoder.convert(e.toJson()))}");
        });
        db.getAllRecords().then((events) {
          JsonEncoder encoder = const JsonEncoder.withIndent('  ');
          print("events===>>${events.map((e) => encoder.convert(e.toJson()))}");
        });
      }
    });
  });*/
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
        Isolate.exit(port);
      });
    });
  });
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.pink,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Picture in Picture Mode'),
      ),
      body: Center(
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => PictureInPicturePage()));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                margin: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                    color: Colors.pink,
                    borderRadius: BorderRadius.circular(12.0)),
                child: const Text(
                  'Picture in Picture Mode',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PictureInPicturePage extends StatefulWidget {
  const PictureInPicturePage({Key? key}) : super(key: key);

  @override
  _PictureInPicturePageState createState() => _PictureInPicturePageState();
}

class _PictureInPicturePageState extends State<PictureInPicturePage> {
  late PipFlutterPlayerController pipFlutterPlayerController;
  final GlobalKey pipFlutterPlayerKey = GlobalKey();

  @override
  void initState() {
    PipFlutterPlayerConfiguration pipFlutterPlayerConfiguration =
        PipFlutterPlayerConfiguration(
            aspectRatio: 16 / 9,
            autoPlay: true,
            fit: BoxFit.contain,
            eventListener: (PipFlutterPlayerEvent event) {
              getPlayerEvent(event);
              return;
            });

    bool isReviewing = false;

    pipFlutterPlayerController = PipFlutterPlayerController(
        pipFlutterPlayerConfiguration, pipLifeCycleCallback: (open) {
      if (open) {
        pipFlutterPlayerController.enablePictureInPicture(pipFlutterPlayerKey);
      } else {
        pipFlutterPlayerController.disablePictureInPicture();
      }
    }, pipFrameCallback: () {
      if (!isReviewing) {
        pipFlutterPlayerController
            .enablePictureInPictureFrame(pipFlutterPlayerKey);
      }
    }, pipInBackgroundCallback: (position, duration) {
      // print("PictureInPicture === >>position=>$position duration=>$duration");
    });
    // 'asset': dataSource.asset,
    // 'package': dataSource.package,
    pipFlutterPlayerController.setupDataSource(PipFlutterPlayerDataSource(
        PipFlutterPlayerDataSourceType.asset,
        'assets/recording.mp4',
        // 'http://vfx.mtime.cn/Video/2019/03/09/mp4/190309153658147087.mp4',
        // 'http://vfx.mtime.cn/Video/2019/02/04/mp4/190204084208765161.mp4',
        // 'http://clips.vorwaerts-gmbh.de/big_buck_bunny.mp4',
        notificationConfiguration:
            const PipFlutterPlayerNotificationConfiguration(
          showNotification: true,
          title: '漫威流水线展示',
          author: '漫威宇宙',
          imageUrl:
              'https://img0.baidu.com/it/u=248545255,575820690&fm=253&fmt=auto&app=138&f=JPEG',
        )));
    pipFlutterPlayerController
        .setPipFlutterPlayerGlobalKey(pipFlutterPlayerKey);
    super.initState();
  }

  void getPlayerEvent(PipFlutterPlayerEvent event) {
    // print(
    //     "统计回放播放时长 event:${event.pipFlutterPlayerEventType.name} ${event.parameters}");
    switch (event.pipFlutterPlayerEventType) {
      case PipFlutterPlayerEventType.progress:
        {
          final Duration progress = event.parameters!['progress'];
          final Duration duration = event.parameters!['duration'];
          /*print(
              "统计回放播放时长 当前进度:progress:${
                  (progress.inMilliseconds.toDouble()/1000.0).toDouble().toStringAsFixed(3)
              } duration:${
                  (duration.inMilliseconds.toDouble()/1000.0).toDouble().toStringAsFixed(3)
              }");*/
        }
        break;
      case PipFlutterPlayerEventType.play:
        {
          print("统计回放播放时长 当前开始播放");
        }
        break;
      case PipFlutterPlayerEventType.pause:
        {
          print("统计回放播放时长 当前暂停播放");
        }
        break;
      case PipFlutterPlayerEventType.finished:
        {
          print("统计回放播放时长 当前完成播放");
        }
        break;
      case PipFlutterPlayerEventType.pipStart:
        {
          print("统计回放播放时长 进入画中画了");
        }
        break;
      case PipFlutterPlayerEventType.pipStop:
        {
          print("统计回放播放时长 停止画中画了");
        }
        break;
      case PipFlutterPlayerEventType.exception:
        {
          print("统计回放播放时长 播放错误了${event.parameters}");
        }
        break;
      default:
        {
          // print(
          //     "统计回放播放时长 event:${event.pipFlutterPlayerEventType.name} ${event.parameters}");
        }
        break;

      /*case PipFlutterPlayerEventType.initialized:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.seekTo:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.openFullscreen:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.hideFullscreen:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.setVolume:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.controlsVisible:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.controlsHiddenStart:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.controlsHiddenEnd:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.setSpeed:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.changedSubtitles:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.changedTrack:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.changedPlayerVisibility:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.changedResolution:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.setupDataSource:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.bufferingStart:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.bufferingUpdate:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.bufferingEnd:
        // TODO: Handle this case.
        break;
      case PipFlutterPlayerEventType.changedPlaylistItem:
        // TODO: Handle this case.
        break;*/
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Picture in Picture player"),
        leading: IconButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            icon: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
            )),
      ),
      body: ClipRect(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Flexible(
              flex: 1,
              fit: FlexFit.loose,
              child: Container(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: PipFlutterPlayer(
                    controller: pipFlutterPlayerController,
                    key: pipFlutterPlayerKey,
                  ),
                ),
                color: Colors.red,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  InkWell(
                    child: Container(
                        width: MediaQuery.of(context).size.width * 0.4,
                        padding: const EdgeInsets.all(8.0),
                        margin: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                            color: Colors.pink,
                            borderRadius: BorderRadius.circular(12.0)),
                        child: const Center(
                            child: Text(
                          "Show PiP",
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ))),
                    onTap: () {
                      pipFlutterPlayerController
                          .enablePictureInPicture(pipFlutterPlayerKey);
                    },
                  ),
                  InkWell(
                    child: Container(
                        width: MediaQuery.of(context).size.width * 0.4,
                        padding: const EdgeInsets.all(8.0),
                        margin: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                            color: Colors.pink,
                            borderRadius: BorderRadius.circular(12.0)),
                        child: const Center(
                            child: Text(
                          "Disable PiP",
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ))),
                    onTap: () async {
                      pipFlutterPlayerController.disablePictureInPicture();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    pipFlutterPlayerKey.currentState?.dispose();
    pipFlutterPlayerController.dispose();
    super.dispose();
  }
}
