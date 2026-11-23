import 'dart:io';

import 'package:dio/dio.dart';

/// A server answer of the form {"detail": "code"} (or an auth/network failure) turned into something a person can read.
class AppError implements Exception {
  AppError(this.code, {this.status});
  final String code;
  final int? status;
  bool get isForbidden => status == 403;
  bool get needsStepUp => code == 'step_up_required' || code == 'session_ended';
  @override
  String toString() => 'AppError($code)';
}

AppError mapError(Object error) {
  if (error is AppError) return error;
  if (error is DioException) {
    final data = error.response?.data;
    final status = error.response?.statusCode;
    if (data is Map && data['detail'] is String) return AppError(data['detail'] as String, status: status);
    if (error.type == DioExceptionType.connectionError || error.error is SocketException) return AppError('offline', status: status);
    if (error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.receiveTimeout || error.type == DioExceptionType.sendTimeout) {
      return AppError('timeout', status: status);
    }
    if (status != null && status >= 500) return AppError('server', status: status);
    if (status == 422) return AppError('invalid_input', status: status);
  }
  return AppError('unknown');
}

/// The ONE place raw errors become text. Never show `e.toString()`.
String userMessage(Object error) {
  final e = mapError(error);
  return switch (e.code) {
    'offline' => 'Pas de connexion. Vérifiez votre réseau et réessayez.',
    'timeout' => 'Le serveur met trop de temps à répondre. Réessayez.',
    'server' => 'Un problème est survenu de notre côté. Réessayez dans un instant.',
    'invalid_credentials' => 'Numéro ou mot de passe incorrect.',
    'not_activated' => "Ce compte n'est pas encore activé. Utilisez le code reçu par WhatsApp.",
    'invalid_code' => 'Code incorrect ou expiré.',
    'weak_password' => 'Mot de passe trop faible : au moins 10 caractères, avec des lettres et des chiffres.',
    'session_expired' => 'Votre session a expiré. Connectez-vous à nouveau.',
    'too_many_attempts' || 'rate_limited' => 'Trop de tentatives. Patientez quelques minutes.',
    'not_staff' || 'wrong_app' || 'forbidden_role' => "Ce compte n'a pas accès à Scolaris pour le personnel.",
    'password_change_required' => 'Vous devez d\'abord choisir un nouveau mot de passe.',
    'step_up_required' => 'Confirmez votre mot de passe pour continuer.',
    'session_ended' => 'Votre session a pris fin. Reconnectez-vous.',
    'phone_invalid' => 'Numéro invalide : 10 chiffres (07, 05 ou 01).',
    'phone_taken' => 'Ce numéro est déjà utilisé.',
    'matricule_already_used' => 'Ce matricule est déjà utilisé par un autre élève.',
    'reference_required' => "La référence de l'opérateur est obligatoire pour ce moyen de paiement.",
    'already_cancelled' => 'Ce paiement est déjà annulé.',
    'fees_locked_by_payments' => 'Les frais de ce niveau ne peuvent plus être modifiés : des paiements ont déjà été reçus.',
    'discount_exceeds_total' => 'La réduction dépasse le montant dû.',
    'option_not_offered' => "Ce service n'est pas proposé pour cette classe.",
    'classroom_exists' => 'Une classe porte déjà ce nom.',
    'year_exists' => 'Cette année scolaire existe déjà.',
    'invalid_input' => 'Vérifiez les informations saisies.',
    _ => e.isForbidden ? 'Cette action n\'est pas disponible pour votre fonction.' : 'Une erreur est survenue. Réessayez.',
  };
}
