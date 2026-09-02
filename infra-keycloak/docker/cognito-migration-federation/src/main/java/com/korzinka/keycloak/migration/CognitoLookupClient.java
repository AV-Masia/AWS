package com.korzinka.keycloak.migration;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * Клиент к Lambda cognito-lookup-by-phone
 * (AWS/infra-korzinka-cognito/migration-bridge.tf) — единственной части
 * моста миграции с прямым доступом к legacy Cognito-пулу. Контракт:
 * POST {"phoneNumber": "..."} с заголовком X-Lookup-Secret ->
 * {"found": bool, "legacyCognitoSub": string|null, "userStatus": string}.
 */
class CognitoLookupClient {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(3))
            .build();

    private final String lookupUrl;
    private final String lookupSecret;

    CognitoLookupClient(String lookupUrl, String lookupSecret) {
        this.lookupUrl = lookupUrl;
        this.lookupSecret = lookupSecret;
    }

    /**
     * Возвращает legacy Cognito {@code sub}, если номер найден в legacy-пуле,
     * иначе {@code null}. Сетевые сбои/некорректный ответ не бросают
     * исключение — лукап не должен ронять сам логин (тот же контракт, что
     * был у AuthService._lookupLegacyCognitoSub на мобильной стороне).
     */
    String lookupLegacyCognitoSub(String phoneNumber) {
        if (lookupUrl == null || lookupUrl.isBlank()) {
            return null;
        }
        try {
            String body = MAPPER.writeValueAsString(new PhoneRequest(phoneNumber));
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(lookupUrl))
                    .timeout(Duration.ofSeconds(5))
                    .header("Content-Type", "application/json")
                    .header("X-Lookup-Secret", lookupSecret == null ? "" : lookupSecret)
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();

            HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200) {
                return null;
            }

            JsonNode json = MAPPER.readTree(response.body());
            if (!json.path("found").asBoolean(false)) {
                return null;
            }
            JsonNode sub = json.path("legacyCognitoSub");
            return sub.isTextual() ? sub.asText() : null;
        } catch (IOException e) {
            return null;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return null;
        }
    }

    private record PhoneRequest(String phoneNumber) {
    }
}
