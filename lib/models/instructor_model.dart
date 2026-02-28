class Instructor {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final String? department;
  final String? officeLocation;
  final String? officeHours;
  final String? bio;
  final DateTime createdAt;

  Instructor({
    required this.id,
    required this.name,
    required this.email,
    this.role = 'Instructor',
    this.phone,
    this.department,
    this.officeLocation,
    this.officeHours,
    this.bio,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Computed properties
  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }

  // Copy with for updates
  Instructor copyWith({
    String? name,
    String? email,
    String? phone,
    String? department,
    String? officeLocation,
    String? officeHours,
    String? bio,
  }) => Instructor(
    id: id,
    name: name ?? this.name,
    email: email ?? this.email,
    role: role,
    phone: phone ?? this.phone,
    department: department ?? this.department,
    officeLocation: officeLocation ?? this.officeLocation,
    officeHours: officeHours ?? this.officeHours,
    bio: bio ?? this.bio,
    createdAt: createdAt,
  );

  // JSON support for backend
  factory Instructor.fromJson(Map<String, dynamic> json) => Instructor(
    id: json['id'],
    name: json['name'],
    email: json['email'],
    role: json['role'] ?? 'Instructor',
    phone: json['phone'],
    department: json['department'],
    officeLocation: json['officeLocation'],
    officeHours: json['officeHours'],
    bio: json['bio'],
    createdAt: json['createdAt'] != null 
      ? DateTime.parse(json['createdAt']) 
      : DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'phone': phone,
    'department': department,
    'officeLocation': officeLocation,
    'officeHours': officeHours,
    'bio': bio,
    'createdAt': createdAt.toIso8601String(),
  };
}