// ignore_for_file: avoid_print
import 'package:api_plus/api_plus.dart';

/// Example demonstrating the Repository Pattern with api_plus.
///
/// This pattern separates data access logic from business logic,
/// making code more testable and maintainable.

// ─── Models ─────────────────────────────────────────────────────────

/// A simple user model.
class User {
  /// The user's unique identifier.
  final int id;

  /// The user's display name.
  final String name;

  /// The user's email address.
  final String email;

  /// Creates a [User].
  const User({required this.id, required this.name, required this.email});

  /// Creates a [User] from a JSON map.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  @override
  String toString() => 'User(id: $id, name: $name, email: $email)';
}

// ─── Repository ─────────────────────────────────────────────────────

/// Repository for user data operations.
///
/// Encapsulates all API calls related to users behind a clean
/// interface. Easy to mock for testing.
class UserRepository {
  final ApiAdapter _api;

  /// Creates a [UserRepository] with the given [api] adapter.
  UserRepository(this._api);

  /// Fetches a user by [id].
  ///
  /// Throws [NotFoundException] if the user doesn't exist.
  /// Throws [NetworkException] on connection failure.
  Future<User> getUser(int id) async {
    final response = await _api.request<Map<String, dynamic>>(
      ApiRequest(path: '/users/$id'),
    );
    return User.fromJson(response.data!);
  }

  /// Fetches all users.
  Future<List<User>> getUsers() async {
    final response = await _api.request<List<dynamic>>(
      const ApiRequest(path: '/users'),
    );
    // Decoded JSON lists are List<dynamic>; convert the items explicitly.
    return response.data!
        .cast<Map<String, dynamic>>()
        .map(User.fromJson)
        .toList();
  }

  /// Creates a new user.
  Future<User> createUser({
    required String name,
    required String email,
  }) async {
    final response = await _api.request<Map<String, dynamic>>(
      ApiRequest(
        path: '/users',
        method: HttpMethod.post,
        headers: const {'Content-Type': 'application/json'},
        body: {'name': name, 'email': email},
      ),
    );
    return User.fromJson(response.data!);
  }
}

// ─── Main ───────────────────────────────────────────────────────────

void main() async {
  // Build the API client
  final api = ApiBuilder('https://jsonplaceholder.typicode.com')
      .clientType(ApiClientType.dio)
      .withRetry(const RetryConfig(maxRetries: 2))
      .withCache(CacheConfig(
        store: MemoryCacheStore(maxEntries: 50),
        defaultTtl: const Duration(minutes: 5),
      ))
      .withLogger(const LoggerConfig(
        level: LogLevel.info,
        format: LogFormat.compact,
        colors: false,
        printCurl: false,
      ))
      .build();

  // Create the repository
  final userRepo = UserRepository(api);

  try {
    // Fetch a single user
    print('--- Fetching user #1 ---');
    final user = await userRepo.getUser(1);
    print('Got: $user');

    // Fetch all users
    print('\n--- Fetching all users ---');
    final users = await userRepo.getUsers();
    print('Got ${users.length} users');
    for (final u in users.take(3)) {
      print('  $u');
    }

    // Fetch same user again (should hit cache)
    print('\n--- Fetching user #1 again (cached) ---');
    final cachedUser = await userRepo.getUser(1);
    print('Got: $cachedUser');
  } on NotFoundException catch (e) {
    print('User not found: ${e.message}');
  } on NetworkException catch (e) {
    print('Network error: ${e.message}');
  } on ApiException catch (e) {
    print('API error: ${e.message}');
  }

  api.close();
}
