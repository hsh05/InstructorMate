class InstructorProfile {
  final String userId;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String? universityName;
  final String? college;
  final String? department;
  final String? jobTitle;
  final String? officeNumber;

  const InstructorProfile({
    required this.userId,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.universityName,
    this.college,
    this.department,
    this.jobTitle,
    this.officeNumber,
  });

  factory InstructorProfile.fromJson(Map<String, dynamic> json) {
    return InstructorProfile(
      userId: json['user_id'] as String,
      fullName: json['full_name'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phone_number'],
      universityName: json['university_name'],
      college: json['college'],
      department: json['department'],
      jobTitle: json['job_title'],
      officeNumber: json['office_number'],
    );
  }

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'phone_number': phoneNumber,
        'university_name': universityName,
        'college': college,
        'department': department,
        'job_title': jobTitle,
        'office_number': officeNumber,
      };

  InstructorProfile copyWith({
    String? fullName,
    String? phoneNumber,
    String? universityName,
    String? college,
    String? department,
    String? jobTitle,
    String? officeNumber,
  }) {
    return InstructorProfile(
      userId: userId,
      email: email,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      universityName: universityName ?? this.universityName,
      college: college ?? this.college,
      department: department ?? this.department,
      jobTitle: jobTitle ?? this.jobTitle,
      officeNumber: officeNumber ?? this.officeNumber,
    );
  }
}