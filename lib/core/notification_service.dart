import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Initialize timezone data
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
      },
    );
  }

  Future<void> showNotification(int id, String title, String body) async {
    await _notificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'general_notifications',
          'General Notifications',
          channelDescription: 'General app notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> scheduleOneTimeReminder({
    required String reminderId,
    required String title,
    required String body,
    required Duration delay,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(delay);

    await _notificationsPlugin.zonedSchedule(
      reminderId.hashCode,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'critical_alerts',
          'Critical Alerts',
          channelDescription: 'Critical health alert reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: null,
    );
  }

  Future<void> scheduleReminders({
    required String scheduleId, // generic string ID
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int> daysOfWeek = const [1, 2, 3, 4, 5, 6, 7], // 1=Mon, 7=Sun
  }) async {
    // We need unique INT ids for notifications. We'll use a combination of scheduleId hash and day index.
    // Base ID from schedule string hash
    final int baseId = scheduleId.hashCode;

    for (final day in daysOfWeek) {
      // Create a unique ID for this day's notification
      // Note: This might collide if baseIds are close, but for a demo it's acceptable.
      // Better approach: bitwise mix or simple offsets if day count is low.
      // Let's assume day is 1-7.
      final int notificationId = baseId + day;

      await _notificationsPlugin.zonedSchedule(
        notificationId,
        title,
        body,
        _nextInstanceOfDayAndTime(day, hour, minute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_reminders',
            'Medication Reminders',
            channelDescription: 'Reminders to take your medications',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  tz.TZDateTime _nextInstanceOfDayAndTime(int day, int hour, int minute) {
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(hour, minute);
    while (scheduledDate.weekday != day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> cancelScheduledReminders(String scheduleId) async {
    final int baseId = scheduleId.hashCode;
    for (int day = 1; day <= 7; day++) {
      await _notificationsPlugin.cancel(baseId + day);
    }
  }

  Future<void> cancelReminder(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }
}
