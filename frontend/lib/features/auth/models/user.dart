class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.surname,
    required this.gender,
    required this.birthdate,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      name: json['name'] as String,
      surname: json['surname'] as String,
      gender: json['gender'] as String,
      birthdate: DateTime.parse(json['birthdate'] as String),
    );
  }

  final int id;
  final String name;
  final String surname;
  final String gender;
  final DateTime birthdate;

  String get fullName => '$name $surname';
}
