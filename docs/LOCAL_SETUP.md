# Decoupled Local Development Guide

This guide details the "Decoupled Local" approach for running the `just_put_it` notes service. In this workflow, the external infrastructure (like the PostgreSQL database) is decoupled from the Spring Boot application lifecycle and is managed manually via `docker-compose`.

## Prerequisites

Before starting, ensure you have the following installed on your machine:
- **Docker & Docker Compose**: Required for running the local PostgreSQL instance.
- **Java 21**: The required JDK version for compilation and execution. *(Note: While the project may currently be configured for Java 17 in `pom.xml`, Java 21 is required for the local environment)*.
- **Maven**: To build, test, and run the Spring Boot application (alternatively, you can use the bundled `./mvnw` wrapper).

## Step 1: Start the Local Database

We use the existing `compose.yaml` file to spin up an ephemeral PostgreSQL instance. 

Navigate to the notes service directory and start the database in detached mode (`-d`) so it runs in the background:

```bash
cd ~/Projects/just_put_it/services/notes_service
docker compose up -d db
```

## Step 2: Verify the Database is Running

Ensure the database container is healthy and actively listening on port 5432.

```bash
# Check if the container is running
docker compose ps

# You should see notes_service-db-1 running and mapping 0.0.0.0:5432->5432/tcp
```

*(Optional)* You can also verify port 5432 is open using `nc` or `telnet`:
```bash
nc -zv localhost 5432
```

## Step 3: Configure Spring Boot Connection Properties

Ensure your local Spring Boot configuration is pointing to this static, decoupled database. 

Verify that your `~/Projects/just_put_it/services/notes_service/src/main/resources/application.properties` (or `application-dev.yml` if you use profiles) contains the following JDBC connection properties matching the Docker Compose configuration:

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/just_put_it
spring.datasource.username=postgres
spring.datasource.password=postgres
spring.jpa.hibernate.ddl-auto=update
```

*(Because we removed `spring-boot-docker-compose`, Spring Boot will rely strictly on these static properties rather than attempting to autodiscover or orchestrate containers).*

## Step 4: Start the Spring Boot Application

With the decoupled database running, you can now start the application manually.

```bash
cd ~/Projects/just_put_it/services/notes_service

# Clean any compiled artifacts and run
./mvnw clean spring-boot:run
```

Wait until you see `Started NotesServiceApplication` and the embedded Tomcat server reports it is listening on port 8080.

## Step 5: Run Automated Tests

To execute the automated integration and unit tests, simply run:

```bash
cd ~/Projects/just_put_it/services/notes_service
./mvnw clean test
```

**Note on Testing:** The automated integration tests (e.g., `AuthRegistrationIntegrationTest`) are configured independently. They do not rely on your manual `docker-compose` PostgreSQL instance. Instead, they either use an embedded H2 database or utilize **Testcontainers** to dynamically provision their own ephemeral, isolated database instances during the test lifecycle. You do not need to manually tear down or start the `docker-compose` stack before running tests.
