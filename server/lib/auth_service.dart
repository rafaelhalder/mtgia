import 'dart:io';
import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';
import 'database.dart';

/// Serviço centralizado de autenticação
/// 
/// Responsabilidades:
/// - Hash e verificação de senhas com bcrypt
/// - Geração e validação de JWT tokens
/// - Operações de autenticação no banco de dados
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  
  late final String _jwtSecret;

  AuthService._internal() {
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
    final secret = env['JWT_SECRET'] ?? Platform.environment['JWT_SECRET'];
    
    if (secret == null || secret.isEmpty) {
      throw StateError(
        'ERRO CRÍTICO: JWT_SECRET não configurado!\n'
        'Adicione no arquivo .env:\n'
        'JWT_SECRET=sua_chave_secreta_aleatoria_aqui\n\n'
        'Gere uma chave segura com: openssl rand -base64 48'
      );
    }
    
    _jwtSecret = secret;
  }

  /// Duração de validade do token (24 horas)
  final Duration _tokenDuration = const Duration(hours: 24);

  /// Cria um hash seguro da senha usando bcrypt
  /// 
  /// Bcrypt é um algoritmo de hashing adaptativo que inclui:
  /// - Salt automático (proteção contra rainbow tables)
  /// - Custo computacional configurável (resistência a força bruta)
  String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  /// Verifica se a senha fornecida corresponde ao hash armazenado
  bool verifyPassword(String password, String hashedPassword) {
    try {
      return BCrypt.checkpw(password, hashedPassword);
    } on ArgumentError catch (e) {
      throw Exception('Invalid password hash format: $e');
    }
  }

  /// Gera um JWT token contendo o ID e username do usuário
  /// 
  /// Estrutura do payload:
  /// - userId: UUID do usuário
  /// - username: Nome de usuário
  /// - iat: Timestamp de emissão
  /// - exp: Timestamp de expiração
  String generateToken(String userId, String username) {
    final jwt = JWT({
      'userId': userId,
      'username': username,
      'iat': DateTime.now().millisecondsSinceEpoch,
    });

    return jwt.sign(SecretKey(_jwtSecret), expiresIn: _tokenDuration);
  }

  /// Valida e decodifica um JWT token
  /// 
  /// Retorna o payload se válido, null se inválido/expirado
  Map<String, dynamic>? verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;

      // Normaliza iat para milissegundos (testes/clients usam ms).
      final iat = payload['iat'];
      if (iat is int && iat < 1000000000000) {
        payload['iat'] = iat * 1000;
      }

      return payload;
    } catch (e) {
      // Token inválido, expirado ou malformado
      return null;
    }
  }

  /// Registra um novo usuário no banco de dados
  /// 
  /// Validações:
  /// - Username único
  /// - Email único
  /// - Senha com hash bcrypt
  /// 
  /// Retorna: Map com 'userId', 'username', 'email' e 'token'
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final db = Database();
    final conn = db.connection;

    // Verificar se username já existe
    final usernameCheck = await conn.execute(
      Sql.named('SELECT id FROM users WHERE username = @username'),
      parameters: {'username': username},
    );

    if (usernameCheck.isNotEmpty) {
      throw Exception('Username já está em uso');
    }

    // Verificar se email já existe
    final emailCheck = await conn.execute(
      Sql.named('SELECT id FROM users WHERE email = @email'),
      parameters: {'email': email},
    );

    if (emailCheck.isNotEmpty) {
      throw Exception('Email já está em uso');
    }

    // Hash da senha
    final hashedPassword = hashPassword(password);

    // Inserir novo usuário
    final result = await conn.execute(
      Sql.named('''
        INSERT INTO users (username, email, password_hash)
        VALUES (@username, @email, @password_hash)
        RETURNING id, username, email
      '''),
      parameters: {
        'username': username,
        'email': email,
        'password_hash': hashedPassword,
      },
    );

    final row = result.first;
    final userId = row[0] as String;
    final returnedUsername = row[1] as String;
    final returnedEmail = row[2] as String;

    // Gerar token
    final token = generateToken(userId, returnedUsername);

    return {
      'userId': userId,
      'username': returnedUsername,
      'email': returnedEmail,
      'token': token,
    };
  }

  /// Autentica um usuário com email e senha
  /// 
  /// Validações:
  /// - Email existe no banco
  /// - Senha corresponde ao hash armazenado
  /// 
  /// Retorna: Map com 'userId', 'username', 'email' e 'token'
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final db = Database();
    final conn = db.connection;

    // Buscar usuário por email
    final result = await conn.execute(
      Sql.named('SELECT id, username, email, password_hash FROM users WHERE email = @email'),
      parameters: {'email': email},
    );

    if (result.isEmpty) {
      throw Exception('Credenciais inválidas');
    }

    final row = result.first;
    final userId = row[0] as String;
    final username = row[1] as String;
    final userEmail = row[2] as String;
    final passwordHash = row[3] as String;

    // Verificar senha
    if (!verifyPassword(password, passwordHash)) {
      throw Exception('Credenciais inválidas');
    }

    // Gerar token
    final token = generateToken(userId, username);

    return {
      'userId': userId,
      'username': username,
      'email': userEmail,
      'token': token,
    };
  }

  /// Busca informações do usuário a partir do token JWT
  /// 
  /// Útil para endpoints que precisam identificar o usuário autenticado
  Future<Map<String, dynamic>?> getUserFromToken(String token) async {
    final payload = verifyToken(token);
    if (payload == null) return null;

    final userId = payload['userId'] as String;
    
    final db = Database();
    final conn = db.connection;

    final result = await conn.execute(
      Sql.named('SELECT id, username, email, display_name, avatar_url FROM users WHERE id = @userId'),
      parameters: {'userId': userId},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    return {
      'id': row[0] as String,
      'username': row[1] as String,
      'email': row[2] as String,
      'display_name': row[3] as String?,
      'avatar_url': row[4] as String?,
    };
  }
}
