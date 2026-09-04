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
 * Провайдер создания пользователя Korzinka в Keycloak по номеру телефона.
 * При первом логине или вызове OTP-эндпоинта материализует локального пользователя
 * с атрибутом phone_number.
 */
public class KorzinkaUserStorageProvider implements UserStorageProvider, UserLookupProvider {

    private final KeycloakSession session;
    private final ComponentModel model;

    KorzinkaUserStorageProvider(KeycloakSession session, ComponentModel model) {
        this.session = session;
        this.model = model;
    }

    @Override
    public UserModel getUserByUsername(RealmModel realm, String username) {
        String phoneNumber = username;

        UserModel user;
        try {
            user = session.users().addUser(realm, phoneNumber);
        } catch (ModelDuplicateException raceLoser) {
            return UserStoragePrivateUtil.userLocalStorage(session).getUserByUsername(realm, phoneNumber);
        }

        user.setEnabled(true);
        user.setFederationLink(model.getId());
        user.setSingleAttribute("phone_number", phoneNumber);

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
