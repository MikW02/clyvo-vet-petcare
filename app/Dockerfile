# syntax=docker/dockerfile:1.6

# ---------- build stage ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /workspace
# Force UTF-8 for the Maven JVM so javac reads the .java source files correctly
# (without this, names like "João" come out double-encoded on hosts with non-UTF-8 default).
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 MAVEN_OPTS="-Dfile.encoding=UTF-8"

COPY pom.xml .
RUN mvn -B -q -e -DskipTests dependency:go-offline

COPY src ./src
RUN mvn -B -q -DskipTests package

# ---------- runtime stage ----------
FROM eclipse-temurin:17-jre-jammy

# create unprivileged user
RUN groupadd --system clyvo && useradd --system --gid clyvo --home /app --shell /sbin/nologin clyvo

WORKDIR /app
COPY --from=build /workspace/target/petcare.jar /app/petcare.jar

RUN chown -R clyvo:clyvo /app
USER clyvo

EXPOSE 8080
# Force UTF-8 at the JVM/locale level so seeded names (João, etc.) round-trip cleanly.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 JAVA_OPTS="-Dfile.encoding=UTF-8"
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/petcare.jar"]
