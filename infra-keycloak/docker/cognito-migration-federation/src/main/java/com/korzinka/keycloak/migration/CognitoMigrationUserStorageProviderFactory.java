package com.korzinka.keycloak.migration;

import org.keycloak.component.ComponentModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.storage.UserStorageProviderFactory;

import java.util.List;

public class CognitoMigrationUserStorageProviderFactory
        implements UserStorageProviderFactory<CognitoMigrationUserStorageProvider> {

    public static final String PROVIDER_ID = "cognito-migration-federation";

    @Override
    public CognitoMigrationUserStorageProvider create(KeycloakSession session, ComponentModel model) {
        return new CognitoMigrationUserStorageProvider(session, model);
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getHelpText() {
        return "Мост миграции Korzinka Cognito -> Keycloak: при первом логине по номеру "
                + "телефона проверяет legacy Cognito-пул и переносит идентичность "
                + "(атрибут legacy_cognito_sub), см. docs/keycloak-migration/MIGRATION.md.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of(
                new ProviderConfigProperty(
                        "lookupUrl",
                        "Cognito lookup URL",
                        "Function URL Lambda cognito-lookup-by-phone (migration-bridge.tf, output migration_bridge_lookup_url)",
                        ProviderConfigProperty.STRING_TYPE,
                        "",
                        false),
                new ProviderConfigProperty(
                        "lookupSecret",
                        "Cognito lookup secret",
                        "Значение заголовка X-Lookup-Secret (output migration_bridge_lookup_secret)",
                        ProviderConfigProperty.PASSWORD,
                        "",
                        true));
    }
}
