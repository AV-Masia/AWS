package com.korzinka.keycloak.migration;

import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserCredentialModel;
import org.keycloak.models.UserModel;
import org.keycloak.services.resource.RealmResourceProvider;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;

/**
 * Реальный OTP вместо мок-кода (см. korzinka/docs/keycloak-migration/CHANGELOG.md,
 * запись "переключение на реальный OTP"). Два REST-эндпоинта поверх realm:
 *
 *   POST /realms/{realm}/cognito-otp/send   {"phoneNumber": "..."}
 *   POST /realms/{realm}/cognito-otp/verify {"phoneNumber": "...", "code": "..."}
 *
 * "Продолжение" второго запроса первым Keycloak понимает не через HTTP-сессию,
 * а через то, что оба запроса адресуют одного и того же пользователя (по
 * phoneNumber == username) — код и время истечения хранятся как его атрибуты
 * (otp_code/otp_expires_at) в той же Aurora Postgres, где живёт весь realm.
 * Проверить значение можно в Admin Console (Users -> Attributes,
 * unmanaged_attribute_policy=ENABLED), через kcadm.sh или прямым SQL к
 * таблице user_attribute.
 *
 * send() создаёт пользователя, если его ещё нет, просто вызывая
 * session.users().getUserByUsername() — это триггерит существующий
 * CognitoMigrationUserStorageProvider.getUserByUsername() (лукап в legacy
 * Cognito), без дублирования этой логики здесь.
 *
 * verify(), убедившись что код верный и не протух, гасит его (одноразовый),
 * ставит его же временным паролем пользователя и делает внутренний ROPC-запрос
 * на localhost (тот же процесс, порт 8080 внутри контейнера) — это
 * переиспользует весь существующий, уже проверенный код выдачи токенов
 * Keycloak (сессии, protocol mappers, refresh token) вместо ручной сборки
 * токенов через внутренние API TokenManager.
 *
 * TEST ONLY: реального SMS-провайдера нет — код только логируется и хранится
 * в БД, см. решение по доставке OTP в журнале миграции.
 */
public class CognitoOtpResourceProvider implements RealmResourceProvider {

    private static final Logger LOG = Logger.getLogger(CognitoOtpResourceProvider.class);
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final long OTP_TTL_MILLIS = Duration.ofMinutes(5).toMillis();
    private static final String MOBILE_CLIENT_ID = "korzinka-mobile";
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    private final KeycloakSession session;

    CognitoOtpResourceProvider(KeycloakSession session) {
        this.session = session;
    }

    @Override
    public Object getResource() {
        return this;
    }

    @Override
    public void close() {
    }

    @POST
    @Path("send")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response send(Map<String, String> body) {
        String phoneNumber = body == null ? null : body.get("phoneNumber");
        if (phoneNumber == null || phoneNumber.isBlank()) {
            return error(400, "invalid_request", "phoneNumber is required");
        }

        RealmModel realm = session.getContext().getRealm();
        UserModel user = session.users().getUserByUsername(realm, phoneNumber);
        if (user == null) {
            return error(400, "user_creation_failed", "Could not provision user");
        }

        String code = generateCode();
        long expiresAt = System.currentTimeMillis() + OTP_TTL_MILLIS;
        user.setSingleAttribute("otp_code", code);
        user.setSingleAttribute("otp_expires_at", String.valueOf(expiresAt));

        LOG.infof("[TEST ONLY] OTP for %s: %s (expires %s)", phoneNumber, code, Instant.ofEpochMilli(expiresAt));

        return Response.ok(Map.of("status", "sent")).build();
    }

    @POST
    @Path("verify")
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Response verify(Map<String, String> body) {
        String phoneNumber = body == null ? null : body.get("phoneNumber");
        String code = body == null ? null : body.get("code");
        if (phoneNumber == null || phoneNumber.isBlank() || code == null || code.isBlank()) {
            return error(400, "invalid_request", "phoneNumber and code are required");
        }

        RealmModel realm = session.getContext().getRealm();
        UserModel user = session.users().getUserByUsername(realm, phoneNumber);
        if (user == null) {
            return error(400, "invalid_grant", "No pending OTP for this phone number");
        }

        String storedCode = user.getFirstAttribute("otp_code");
        String storedExpiry = user.getFirstAttribute("otp_expires_at");
        if (storedCode == null || storedExpiry == null) {
            return error(400, "invalid_grant", "No pending OTP for this phone number");
        }

        long expiresAt;
        try {
            expiresAt = Long.parseLong(storedExpiry);
        } catch (NumberFormatException e) {
            expiresAt = 0L;
        }

        if (System.currentTimeMillis() > expiresAt) {
            clearOtp(user);
            return error(400, "invalid_grant", "OTP expired");
        }

        if (!storedCode.equals(code)) {
            return error(400, "invalid_grant", "Incorrect OTP code");
        }

        // Одноразовый код — гасим сразу, независимо от исхода обмена на токены ниже.
        clearOtp(user);
        user.credentialManager().updateCredential(UserCredentialModel.password(code));

        // Обязательный коммит перед внутренним HTTP-вызовом ниже: без него
        // смена пароля видна только в транзакции текущего запроса, а ROPC на
        // /token — это отдельный HTTP-запрос со своей транзакцией к той же
        // Postgres (READ COMMITTED) и без коммита не увидит новый credential
        // ("invalid_user_credentials", проверено эмпирически).
        session.getTransactionManager().commit();

        return exchangeForTokens(realm, phoneNumber, code);
    }

    private void clearOtp(UserModel user) {
        user.removeAttribute("otp_code");
        user.removeAttribute("otp_expires_at");
    }

    private Response exchangeForTokens(RealmModel realm, String phoneNumber, String code) {
        // scope=openid обязателен явно — без него ROPC отдаёт только
        // access_token/refresh_token, без id_token (проверено эмпирически),
        // а мобильный код полагается именно на id_token (см. AuthService).
        String form = "grant_type=password"
                + "&client_id=" + urlEncode(MOBILE_CLIENT_ID)
                + "&username=" + urlEncode(phoneNumber)
                + "&password=" + urlEncode(code)
                + "&scope=openid";

        URI tokenEndpoint = URI.create(
                "http://localhost:8080/realms/" + realm.getName() + "/protocol/openid-connect/token");

        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(tokenEndpoint)
                    .timeout(Duration.ofSeconds(10))
                    .header("Content-Type", "application/x-www-form-urlencoded")
                    .POST(HttpRequest.BodyPublishers.ofString(form))
                    .build();
            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            return Response.status(response.statusCode())
                    .entity(response.body())
                    .type(MediaType.APPLICATION_JSON)
                    .build();
        } catch (IOException e) {
            LOG.error("Internal token exchange failed", e);
            return error(500, "server_error", "Token exchange failed");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            LOG.error("Internal token exchange interrupted", e);
            return error(500, "server_error", "Token exchange failed");
        }
    }

    private static String generateCode() {
        int value = RANDOM.nextInt(1_000_000);
        return String.format("%06d", value);
    }

    private static String urlEncode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private static Response error(int status, String error, String description) {
        return Response.status(status)
                .entity(Map.of("error", error, "error_description", description))
                .type(MediaType.APPLICATION_JSON)
                .build();
    }
}
