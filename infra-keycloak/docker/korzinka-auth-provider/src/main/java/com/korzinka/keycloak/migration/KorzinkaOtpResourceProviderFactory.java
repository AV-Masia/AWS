package com.korzinka.keycloak.migration;

import org.keycloak.Config;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.services.resource.RealmResourceProvider;
import org.keycloak.services.resource.RealmResourceProviderFactory;

/**
 * Регистрирует {@link KorzinkaOtpResourceProvider} под путём /realms/{realm}/otp/*
 */
public class KorzinkaOtpResourceProviderFactory implements RealmResourceProviderFactory {

    public static final String ID = "otp";

    @Override
    public RealmResourceProvider create(KeycloakSession session) {
        return new KorzinkaOtpResourceProvider(session);
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
