# Кастомный образ Keycloak с AWS JDBC Wrapper (IAM-аутентификация к Aurora).
# Нужен потому, что этот Aurora-кластер в аккаунте создаётся только в
# Express-режиме (без VPC) и принимает исключительно IAM DB auth token,
# а не статический пароль — стандартный образ Keycloak это не умеет.

FROM maven:3.9-eclipse-temurin-21 AS deps
WORKDIR /build
COPY pom.xml .
RUN mvn -q -B dependency:copy-dependencies -DincludeScope=runtime -DoutputDirectory=/deps

# SPI провайдера аутентификации Korzinka по номеру телефона (см. korzinka-auth-provider/).
# Собирается отдельным модулем — сам jar тонкий, все Keycloak/Jackson-зависимости
# provided (уже есть на classpath образа ниже).
FROM maven:3.9-eclipse-temurin-21 AS auth-spi
WORKDIR /build
COPY korzinka-auth-provider/pom.xml .
COPY korzinka-auth-provider/src ./src
RUN mvn -q -B package

FROM quay.io/keycloak/keycloak:26.0
COPY --from=deps /deps/*.jar /opt/keycloak/providers/
COPY --from=auth-spi /build/target/korzinka-auth-provider-*.jar /opt/keycloak/providers/
RUN /opt/keycloak/bin/kc.sh build --db=postgres --db-driver=software.amazon.jdbc.Driver --health-enabled=true

