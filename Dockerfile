# Stage 1: Build WAR with Maven
FROM --platform=linux/amd64 maven:3.6-jdk-8 AS builder

WORKDIR /app
COPY settings.xml /root/.m2/settings.xml
COPY pom.xml .
COPY ofcms-admin/pom.xml ofcms-admin/pom.xml
COPY ofcms-core/pom.xml ofcms-core/pom.xml
COPY ofcms-model/pom.xml ofcms-model/pom.xml
COPY ofcms-front/pom.xml ofcms-front/pom.xml
COPY ofcms-api/pom.xml ofcms-api/pom.xml

# Download dependencies first (cached layer)
RUN mvn dependency:go-offline -B || true

# Copy source code
COPY ofcms-admin/ ofcms-admin/
COPY ofcms-core/ ofcms-core/
COPY ofcms-model/ ofcms-model/
COPY ofcms-front/ ofcms-front/
COPY ofcms-api/ ofcms-api/

# Build WAR
RUN mvn clean package -DskipTests -B

# Stage 2: Run with Tomcat
FROM --platform=linux/amd64 tomcat:8.5-jdk8

# Install mysql client for healthcheck
RUN apt-get update && apt-get install -y default-mysql-client && rm -rf /var/lib/apt/lists/*

# Remove default webapps
RUN rm -rf /usr/local/tomcat/webapps/*

# Copy WAR from builder
COPY --from=builder /app/ofcms-admin/target/ofcms-admin.war \
     /usr/local/tomcat/webapps/ofcms-admin.war

# Extract WAR so we can modify config at runtime
RUN cd /usr/local/tomcat/webapps && \
    mkdir ofcms-admin && \
    cd ofcms-admin && \
    jar xf ../ofcms-admin.war && \
    rm ../ofcms-admin.war

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["catalina.sh", "run"]
