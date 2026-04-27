// lib/models/instructor_model.dart

class Instructor {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? universityName;
  final String? college;
  final String? department;
  final String? jobTitle;
  final String? officeLocation;
  final String? bio;
  final DateTime createdAt;

  Instructor({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.universityName,
    this.college,
    this.department,
    this.jobTitle,
    this.officeLocation,
    this.bio,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Computed initials for Avatar
  String get initials {
    if (name.isEmpty) return '??';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }

  // Parses the new unified backend JSON
  factory Instructor.fromJson(Map<String, dynamic> json) => Instructor(
    id: json['id']?.toString() ?? json['user_id']?.toString() ?? '',
    name: json['name'] ?? json['full_name'] ?? '',
    email: json['email'] ?? '',
    phone: json['phone'] ?? json['phone_number'],
    universityName: json['university_name'],
    college: json['college'],
    department: json['department'],
    jobTitle: json['job_title'] ?? json['role'] ?? 'Instructor',
    officeLocation: json['officeLocation'] ?? json['office_number'],
    bio: json['bio'],
    createdAt: json['createdAt'] != null 
      ? DateTime.parse(json['createdAt']) 
      : DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': name,
    'email': email,
    'phone_number': phone,
    'university_name': universityName,
    'college': college,
    'department': department,
    'job_title': jobTitle,
    'office_number': officeLocation,
    'bio': bio,
    'createdAt': createdAt.toIso8601String(),
  };

  Instructor copyWith({
    String? name,
    String? email,
    String? phone,
    String? universityName,
    String? college,
    String? department,
    String? jobTitle,
    String? officeLocation,
    String? bio,
  }) => Instructor(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    universityName: universityName ?? this.universityName,
    college: college ?? this.college,
    department: department ?? this.department,
    jobTitle: jobTitle ?? this.jobTitle,
    officeLocation: officeLocation ?? this.officeLocation,
    bio: bio ?? this.bio,
    createdAt: createdAt,
  );
}