package com.korzinka.keycloak.migration;

import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.storage.UserStorageProviderFactory;

import java.util.Collections;
import java.util.List;

public class KorzinkaUserStorageProviderFactory
        implements UserStorageProviderFactory<KorzinkaUserStorageProvider> {

    public static final String PROVIDER_ID = "korzinka-phone-storage";

    @Override
    public KorzinkaUserStorageProvider create(KeycloakSession session, ComponentModel model) {
        return new KorzinkaUserStorageProvider(session, model);
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getHelpText() {
        return "Провайдер пользователей Korzinka: при первом логине по номеру телефона "
                + "материализует локального пользователя в Keycloak.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return Collections.emptyList();
    }
}
