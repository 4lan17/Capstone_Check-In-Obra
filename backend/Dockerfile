# Las imágenes base van fijadas por digest (SEG11, S-15): un tag como 21-jre-alpine se mueve, y con
# él lo que se construye. Dependabot (ecosistema docker) propone el digest nuevo en un PR.
FROM maven:3.9-eclipse-temurin-21@sha256:99e61abcff91a9b1333463bd8451fb18495d6eba9250ac66a338b518f8278320 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:24-jre-alpine@sha256:4044b6c87cb088885bcd0220f7dc7a8a4aab76577605fa471945d2e98270741f
WORKDIR /app
# No corre como root: un fallo de la API no entrega un shell de root dentro del contenedor.
RUN addgroup -S app && adduser -S -G app -H -s /sbin/nologin app
# Contraseñas de las bases que crea la API (alta de empresas): debe ser un volumen persistente.
RUN mkdir /secretos && chown app:app /secretos && chmod 700 /secretos
ENV SECRETOS_DIR=/secretos
COPY --from=build --chown=app:app /app/target/*.jar app.jar
USER app
EXPOSE 8080
# Liveness del actuator: solo dice que la aplicación responde (no prueba la base, que es una por empresa).
HEALTHCHECK --interval=15s --timeout=3s --start-period=90s --retries=5 \
  CMD wget -q -O /dev/null http://localhost:8080/actuator/health/liveness || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
