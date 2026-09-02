package com.korzinka.keycloak.migration;

import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.ModelDuplicateException;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.storage.UserStoragePrivateUtil;
import org.keycloak.storage.UserStorageProvider;
import org.keycloak.storage.user.UserLookupProvider;

/**
 * Мост миграции Korzinka Cognito -> Keycloak по номеру телефона (см.
 * korzinka/docs/keycloak-migration/MIGRATION.md, решение от 2026-09-01).
 * Заменяет временный HTTP-вызов из мобильного provisioning-кода
 * (AuthService._ensureKeycloakTestUser/_lookupLegacyCognitoSub) — теперь
 * lookup в legacy Cognito и создание пользователя происходят на сервере,
 * при первом ROPC-логине по неизвестному username (номеру телефона), без
 * доверия мобильному клиенту и без секрета admin_cli в мобильной сборке.
 *
 * Keycloak вызывает getUserByUsername() только после того, как сам не
 * нашёл пользователя в локальном хранилище — то есть это гарантированно
 * первый логин этим номером (либо первый вызов /cognito-otp/send для него,
 * см. CognitoOtpResourceProvider). Мы материализуем настоящего локального
 * пользователя (не виртуальный federation-proxy) с атрибутами
 * phone_number/legacy_cognito_sub. Password-credential здесь больше не
 * ставится — реальный OTP-код и его сверку делает CognitoOtpResourceProvider
 * (send/verify), credential выставляется только на verify(), одноразово.
 * Повторные логины этим же номером идут полностью локально, без повторного
 * обращения к этому провайдеру.
 */
public class CognitoMigrationUserStorageProvider implements UserStorageProvider, UserLookupProvider {

    private final KeycloakSession session;
    private final ComponentModel model;
    private final CognitoLookupClient lookupClient;

    CognitoMigrationUserStorageProvider(KeycloakSession session, ComponentModel model) {
        this.session = session;
        this.model = model;
        this.lookupClient = new CognitoLookupClient(
                model.get("lookupUrl"),
                model.get("lookupSecret"));
    }

    @Override
    public UserModel getUserByUsername(RealmModel realm, String username) {
        String phoneNumber = username;
        String legacyCognitoSub = lookupClient.lookupLegacyCognitoSub(phoneNumber);

        UserModel user;
        try {
            user = session.users().addUser(realm, phoneNumber);
        } catch (ModelDuplicateException raceLoser) {
            // Гонка двух параллельных первых логинов тем же номером — второй
            // просто читает то, что уже успел создать первый.
            return UserStoragePrivateUtil.userLocalStorage(session).getUserByUsername(realm, phoneNumber);
        }

        user.setEnabled(true);
        user.setFederationLink(model.getId());
        user.setSingleAttribute("phone_number", phoneNumber);
        if (legacyCognitoSub != null) {
            user.setSingleAttribute("legacy_cognito_sub", legacyCognitoSub);
        }

        return user;
    }

    @Override
    public UserModel getUserById(RealmModel realm, String id) {
        return null;
    }

    @Override
    public UserModel getUserByEmail(RealmModel realm, String email) {
        return null;
    }

    @Override
    public void close() {
    }
}
