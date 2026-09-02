package com.korzinka.keycloak.migration;

import org.keycloak.Config;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.services.resource.RealmResourceProvider;
import org.keycloak.services.resource.RealmResourceProviderFactory;

/**
 * Регистрирует {@link CognitoOtpResourceProvider} под путём /realms/{realm}/cognito-otp/*
 * (id фабрики == сегмент пути после /realms/{realm}/).
 */
public class CognitoOtpResourceProviderFactory implements RealmResourceProviderFactory {

    public static final String ID = "cognito-otp";

    @Override
    public RealmResourceProvider create(KeycloakSession session) {
        return new CognitoOtpResourceProvider(session);
    }

    @Override
    public void init(Config.Scope config) {
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
    }

    @Override
    public void close() {
    }

    @Override
    public String getId() {
        return ID;
    }
}
