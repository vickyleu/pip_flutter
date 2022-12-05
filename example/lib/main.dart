import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pip_flutter/pipflutter_player.dart';
import 'package:pip_flutter/pipflutter_player_notification_configuration.dart';

void main() {
  runApp(const MyApp());
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
  @override
  _PictureInPicturePageState createState() => _PictureInPicturePageState();
}

class _PictureInPicturePageState extends State<PictureInPicturePage> {
  late PipFlutterPlayerController pipFlutterPlayerController;
  final GlobalKey pipFlutterPlayerKey = GlobalKey();

  @override
  void initState() {
    PipFlutterPlayerConfiguration pipFlutterPlayerConfiguration =
        const PipFlutterPlayerConfiguration(
      aspectRatio: 16 / 9,
      autoPlay: true,
      fit: BoxFit.contain,
    );

    bool isReviewing = false;

    pipFlutterPlayerController = PipFlutterPlayerController(
        pipFlutterPlayerConfiguration,
        pipLifeCycleCallback: (open) {
          if (open) {
          pipFlutterPlayerController.enablePictureInPicture(pipFlutterPlayerKey);
      }
          else {
            pipFlutterPlayerController.disablePictureInPicture();
          }
    },
        pipFrameCallback: (){
          if(!isReviewing){
            pipFlutterPlayerController.enablePictureInPictureFrame(pipFlutterPlayerKey);
          }
    },
        pipInBackgroundCallback: (position,duration){
          print("PictureInPicture === >>position=>$position duration=>$duration");
        }
    );
    pipFlutterPlayerController.setupDataSource(PipFlutterPlayerDataSource(
        PipFlutterPlayerDataSourceType.network,
        'https://sourceqn3.uooconline.com/course900/20210207%E4%BF%AE%E6%94%B9%E4%B8%8A%E4%BC%A0%E6%9B%B4%E6%96%B0/1.3%E5%85%AC%E5%8F%B8%E5%88%B6%E4%BC%81%E4%B8%9A.mp4',
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
        )
    )
    );
    pipFlutterPlayerController
        .setPipFlutterPlayerGlobalKey(pipFlutterPlayerKey);
    super.initState();
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
      body: Column(
        children: [
          const SizedBox(height: 20),
          Flexible(
            flex: 1,
            fit: FlexFit.loose,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: PipFlutterPlayer(
                controller: pipFlutterPlayerController,
                key: pipFlutterPlayerKey,
              ),
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
    );
  }
}
