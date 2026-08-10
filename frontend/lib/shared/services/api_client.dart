import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';

class ApiClient {
  ApiClient._internal()
      : dio = Dio(
          BaseOptions(
            baseUrl: AppConstants.apiBaseUrl,
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

  static final ApiClient instance = ApiClient._internal();

  final Dio dio;
}
