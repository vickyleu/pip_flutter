import 'package:sqflite/sqflite.dart';

class PipVideoRecord {
  final String eventName;
  final String eventTime;
  final int eventProgress;
  final int eventInterval;
  final String videoId;
  final String userId;
  final String? videoRecordId;

  PipVideoRecord({
    required this.eventName,
    required this.eventTime,
    required this.eventProgress,
    required this.eventInterval,
    required this.videoId,
    required this.userId,
    this.videoRecordId,
  });

  Map<String, dynamic> toJson() {
    return {
      'event_name': eventName,
      'event_time': eventTime,
      'event_progress': eventProgress,
      'event_interval': eventInterval,
      'video_id': videoId,
      'user_id': userId,
      'video_record_id': videoRecordId,
    };
  }

  static PipVideoRecord fromJson(Map<String, dynamic> json) {
    return PipVideoRecord(
      eventName: json['event_name'],
      eventTime: json['event_time'],
      eventProgress: json['event_progress'],
      eventInterval: json['event_interval'],
      videoId: json['video_id'],
      userId: json['user_id'],
      videoRecordId: json['video_record_id'],
    );
  }
}

class PipVideoRecordDatabase {
  late Database _database;

// 初始化数据库
  Future<void> init() async {
    _database = await openDatabase(
      'video_record.db',
      version: 3,
      onCreate: (Database db, int version) async {
        await db.execute(
          'CREATE TABLE records (event_name TEXT, event_time TEXT, event_progress INTEGER,event_interval INTEGER, video_id TEXT, user_id TEXT, video_record_id TEXT)',
        );
      },
      onUpgrade: (Database db, int oldVersion, int newVersion)async{
        if(newVersion>oldVersion){
          await db.execute(
            'drop TABLE records',
          );
          await db.execute(
            'CREATE TABLE records (event_name TEXT, event_time TEXT, event_progress INTEGER,event_interval INTEGER,  video_id TEXT, user_id TEXT, video_record_id TEXT)',
          );
        }
      }
    );
  }

// 添加记录
  void addRecord(PipVideoRecord record) async {
//     if (record.eventName == 'mark') {
// // 对于频繁的mark操作，使用compute()进行空间隔离
//       compute(addRecordHelper, MapEntry(record, this));
//     } else {
    await _database.insert(
      'records',
      record.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // }
  }

// 辅助函数，避免数据库死锁
  static void addRecordHelper(
      MapEntry<PipVideoRecord, PipVideoRecordDatabase> entry) async {
    // WidgetsFlutterBinding.ensureInitialized();
    final record = entry.key;
    final database = entry.value;
    database._database.insert(
      'records',
      record.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

// 获取单个user_id的所有操作
  Future<List<PipVideoRecord>> getUserRecords(String userId) async {
    final List<Map<String, dynamic>> maps = await _database.query(
      'records',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return List.generate(
      maps.length,
      (i) => PipVideoRecord.fromJson(maps[i]),
    );
  }
  // 获取所有操作
  Future<List<PipVideoRecord>> getAllRecords() async {
    final List<Map<String, dynamic>> maps = await _database.query(
      'records'
    );
    return List.generate(
      maps.length,
      (i) => PipVideoRecord.fromJson(maps[i]),
    );
  }

// 删除单个user_id的所有数据
  void deleteUserRecords(String userId) async {
    await _database.delete(
      'records',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
