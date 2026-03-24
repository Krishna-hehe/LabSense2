import 'utils/unit_sanitizer.dart';

class TestResult {
  final String name;
  final String originalName;
  final String loinc;
  final String result;
  final String unit;
  final String reference;
  final String status;

  TestResult({
    required this.name,
    this.originalName = '',
    required this.loinc,
    required this.result,
    required this.unit,
    required this.reference,
    required this.status,
  });

  factory TestResult.fromJson(Map<String, dynamic> json) {
    return TestResult(
      name: json['test_name'] ?? json['name'] ?? '',
      originalName: json['original_name'] ?? '',
      loinc: json['loinc'] ?? json['loinc_code'] ?? '',
      result:
          json['result_value']?.toString() ?? json['result']?.toString() ?? '',
      unit: UnitSanitizer.clean(json['unit']?.toString()) ?? '',
      reference: json['reference_range'] ?? json['reference'] ?? '',
      status: json['status'] ?? 'Normal',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'test_name': name,
      'original_name': originalName,
      'loinc': loinc,
      'result_value': result,
      'unit': unit,
      'reference_range': reference,
      'status': status,
    };
  }
}

class LabReport {
  final String id;
  final DateTime date;
  final String labName;
  final int testCount;
  final int abnormalCount;
  final String status;
  final bool isSelected;
  final String? storagePath;
  final List<TestResult>? testResults;

  LabReport({
    required this.id,
    required this.date,
    required this.labName,
    required this.testCount,
    this.abnormalCount = 0,
    required this.status,
    this.isSelected = false,
    this.storagePath,
    this.testResults,
  });

  factory LabReport.fromJson(Map<String, dynamic> json) {
    return LabReport(
      id: json['id']?.toString() ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      labName: json['lab_name'] ?? 'Unknown Lab',
      testCount: json['tests'] is int
          ? json['tests']
          : (json['test_results'] as List?)?.length ?? 0,
      abnormalCount:
          json['abnormal_count'] ??
          (json['test_results'] as List?)?.where((t) {
            final s = t['status']?.toString().toLowerCase() ?? '';
            return s == 'abnormal' || s == 'high' || s == 'low';
          }).length ??
          0,
      status: json['status'] ?? 'Normal',
      storagePath: json['storage_path'],
      testResults: (json['test_results'] as List?)
          ?.map((t) => TestResult.fromJson(t))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'lab_name': labName,
      'tests': testCount,
      'abnormal_count': abnormalCount,
      'status': status,
      'storage_path': storagePath,
      'test_results': testResults?.map((t) => t.toJson()).toList(),
    };
  }
}

class UserProfile {
  final String id;
  final String userId;
  final String firstName;
  final String lastName; // Optional in UI, but good for model
  final String relationship; // 'Self', 'Spouse', 'Child', 'Parent', 'Other'
  final String avatarColor; // Hex string e.g. "0xFF123456"
  final String? avatarUrl;
  final DateTime? dateOfBirth;
  final String gender; // 'Male', 'Female', 'Other'
  final List<String> conditions;

  UserProfile({
    required this.id,
    required this.userId,
    required this.firstName,
    this.lastName = '',
    this.relationship = 'Self',
    this.avatarColor = '0xFF2196F3', // Default Blue
    this.avatarUrl,
    this.dateOfBirth,
    this.gender = 'Other',
    this.conditions = const [],
  });

  String get fullName => '$firstName $lastName'.trim();

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    return UserProfile(
      id: id,
      userId: json['user_id']?.toString() ?? id,
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      relationship: json['relationship'] ?? 'Self',
      avatarColor: json['avatar_color'] ?? '0xFF2196F3',
      avatarUrl: json['avatar_url'],
      dateOfBirth: DateTime.tryParse(json['date_of_birth'] ?? ''),
      gender: json['gender'] ?? 'Other',
      conditions: List<String>.from(json['conditions'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'first_name': firstName,
      'last_name': lastName,
      'relationship': relationship,
      'avatar_color': avatarColor,
      'avatar_url': avatarUrl,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'gender': gender,
      'conditions': conditions,
    };
  }
}

class Medication {
  final String id;
  final String userId;
  final String profileId;
  final String name;
  final String dosage;
  final String frequency; // e.g. "Daily", "Weekly", "As Needed"
  final DateTime startDate;
  final DateTime? endDate;
  final List<ReminderSchedule>? schedules;
  final String? imageUrl;
  final bool isActive;

  Medication({
    required this.id,
    required this.userId,
    required this.profileId,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.schedules,
    this.imageUrl,
    this.isActive = true,
  });

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      profileId: json['profile_id']?.toString() ?? '',
      name: json['name'] ?? '',
      dosage: json['dosage'] ?? '',
      frequency: json['frequency'] ?? 'Daily',
      startDate: DateTime.tryParse(json['start_date'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['end_date'] ?? ''),
      schedules: (json['reminder_schedules'] as List?)
          ?.map((s) => ReminderSchedule.fromJson(s))
          .toList(),
      imageUrl: json['image_url'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    final val = <String, dynamic>{
      'user_id': userId,
      'profile_id': profileId,
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'image_url': imageUrl,
      'is_active': isActive,
    };
    if (id.isNotEmpty) {
      val['id'] = id;
    }
    return val;
  }
}

class ReminderSchedule {
  final String id;
  final String medicationId;
  final String time; // "HH:mm" 24-hour format
  final List<int> daysOfWeek; // 1 = Monday, 7 = Sunday

  ReminderSchedule({
    required this.id,
    required this.medicationId,
    required this.time,
    required this.daysOfWeek,
  });

  factory ReminderSchedule.fromJson(Map<String, dynamic> json) {
    return ReminderSchedule(
      id: json['id']?.toString() ?? '',
      medicationId: json['medication_id']?.toString() ?? '',
      time: json['time'] ?? '08:00',
      daysOfWeek:
          (json['days_of_week'] as List?)?.cast<int>() ?? [1, 2, 3, 4, 5, 6, 7],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'medication_id': medicationId,
      'time': time,
      'days_of_week': daysOfWeek,
    };
  }
}
